/**
 * JayOh Logger — org-local logging utility.
 *
 * Basic usage:
 *   Logger.error('CBQuoteShippingAddressHandler.handle', 'Callout failed', ex);
 *   Logger.info('MyBatch.execute', 'Processed ' + records.size() + ' records');
 *   Logger.saveLog(); // call once, ideally in a `finally` block — see below
 *
 * Fluent usage:
 *   Logger.error('CBHttpClient.patch', 'Callout failed', ex)
 *       .setRecord(quote.Id)
 *       .addTag('chargebee');
 *
 * ---- Governor limits: why saveLog()/flush() work the way they do ----
 * EventBus.publish() is capped at 150 calls PER TRANSACTION (a hard Apex
 * governor limit). Critically, a single publish(list) call counts as ONE
 * call no matter how many events are in the list — same as
 * Database.insert(list) counting as one DML statement regardless of list
 * size. Entries are buffered in memory and only published when
 * saveLog()/flush() is called explicitly. Auto-flushing per log call (an
 * earlier version of this class did this on every ERROR) means a loop
 * logging many errors would make one publish() call per error and risk
 * that 150-per-transaction ceiling — buffering avoids this entirely.
 * The trade-off: A buffered entry that never reaches saveLog() is silently
 * lost, so call it in a `finally` block, which runs even when an exception
 * propagates past your `catch`.
 *
 * Platform events also carry a separate, ORG-WIDE daily/hourly publish
 * allocation (varies by edition). Batching solves the per-transaction risk;
 * it does not remove this ceiling — worth monitoring in a very high-volume org.
 *
 * ---- Save methods ----
 * Logger.SaveMethod.EVENT_BUS (default) — publishes as a platform event;
 *   survives a transaction rollback, since platform events commit independently.
 * Logger.SaveMethod.QUEUEABLE — defers the insert to a separate async
 *   transaction with its own governor limits. Trades rollback-safety for
 *   limit isolation.
 * Logger.SaveMethod.REST — inserts via a synchronous callout to this org's
 *   own REST API using the current session, avoiding a local DML statement
 *   entirely. EXPERIMENTAL — see LogRestSaver's class comment.
 * Logger.SaveMethod.SYNCHRONOUS_DML — bypasses platform events and inserts
 *   directly and synchronously. Loses rollback-safety: if the surrounding
 *   transaction rolls back, so do your log entries.
 *
 * ---- Other controls ----
 * setParentLogTransactionId(String) — relates a batch/queueable job's own
 *   transaction (which always gets a new transaction id) back to the log
 *   that kicked it off, via Log__c.ParentLog__c.
 * flushBuffer() — discards everything buffered, without saving it.
 * suspendSaving()/resumeSaving() — ignore log calls entirely until resumed.
 *
 * The minimum level to actually log is read once per transaction from
 * Log_Level_Setting__mdt (see getMinLevel()), keyed by Profile/Permission Set.
 * Simple field-name/value masking runs on message + context before persist.
 */
public without sharing class Logger {

    public enum SaveMethod { EVENT_BUS, QUEUEABLE, REST, SYNCHRONOUS_DML }

    private static final List<Log_Entry_Event__e> BUFFER = new List<Log_Entry_Event__e>();
    private static Integer minLevelOrdCache = null;
    private static String transactionIdCache = null;
    private static String parentLogTransactionId = null;
    private static Boolean suspended = false;
    private static SaveMethod defaultSaveMethod = SaveMethod.EVENT_BUS;

    // ---- Public API: logging -----------------------------------------------

    public static LogEntryBuilder error(String source, String message) {
        return log('ERROR', source, message, null, null);
    }

    public static LogEntryBuilder error(String source, String message, Exception ex) {
        return log('ERROR', source, message, ex, null);
    }

    public static LogEntryBuilder error(String source, String message, Exception ex, Id relatedRecordId) {
        return log('ERROR', source, message, ex, relatedRecordId);
    }

    public static LogEntryBuilder error(String source, LogMessage message) {
        return log('ERROR', source, message.getMessage(), null, null);
    }

    public static LogEntryBuilder warn(String source, String message) {
        return log('WARN', source, message, null, null);
    }

    public static LogEntryBuilder warn(String source, LogMessage message) {
        return log('WARN', source, message.getMessage(), null, null);
    }

    public static LogEntryBuilder info(String source, String message) {
        return log('INFO', source, message, null, null);
    }

    public static LogEntryBuilder info(String source, LogMessage message) {
        return log('INFO', source, message.getMessage(), null, null);
    }

    public static LogEntryBuilder debug(String source, String message) {
        return log('DEBUG', source, message, null, null);
    }

    public static LogEntryBuilder debug(String source, LogMessage message) {
        return log('DEBUG', source, message.getMessage(), null, null);
    }

    // ---- Public API: saving -------------------------------------------------

    /** Alias for saveLog() using the current default save method. */
    public static void flush() {
        saveLog();
    }

    /** Publish/insert everything buffered so far, using the current default save method. */
    public static void saveLog() {
        saveLog(defaultSaveMethod);
    }

    /**
     * Publish/insert everything buffered so far using a specific save method
     * for this call only — does not change the default used by later calls.
     */
    public static void saveLog(SaveMethod method) {
        if (BUFFER.isEmpty() || suspended) {
            return;
        }
        List<Log_Entry_Event__e> toSave = BUFFER.deepClone();
        BUFFER.clear();

        switch on method {
            when EVENT_BUS {
                EventBus.publish(toSave); // one call regardless of list size
            }
            when SYNCHRONOUS_DML {
                LogEntryEventHandler.handle(toSave); // direct, synchronous — loses rollback-safety
            }
            when QUEUEABLE {
                System.enqueueJob(new LogSaveQueueable(toSave)); // separate async transaction/limits
            }
            when REST {
                LogRestSaver.save(toSave); // experimental — see LogRestSaver class comment
            }
        }
    }

    /** Sets the save method subsequent saveLog()/flush() calls use by default. */
    public static void setSaveMethod(SaveMethod method) {
        defaultSaveMethod = method;
    }

    /** Discards everything buffered so far WITHOUT saving it. */
    public static void flushBuffer() {
        BUFFER.clear();
    }

    /** Ignores all log calls until resumeSaving() is called — they're simply not buffered. */
    public static void suspendSaving() {
        suspended = true;
    }

    public static void resumeSaving() {
        suspended = false;
    }

    // ---- Public API: correlation ---------------------------------------------

    /**
     * Relates this transaction's Log__c back to another one — typically used
     * in a batch/queueable job's start()/execute()/finish() (each of which
     * runs in its own transaction with its own transaction id) to link them
     * all back to the transaction that kicked the job off:
     *
     *   public Database.QueryLocator start(Database.BatchableContext bc) {
     *       this.originalTransactionId = Logger.getTransactionId();
     *       ...
     *   }
     *   public void execute(Database.BatchableContext bc, List<SObject> scope) {
     *       Logger.setParentLogTransactionId(this.originalTransactionId);
     *       ...
     *   }
     */
    public static void setParentLogTransactionId(String transactionId) {
        parentLogTransactionId = transactionId;
    }

    /** The current transaction's id — same value used to group this transaction's Log__c header. */
    public static String getTransactionId() {
        return getTransactionIdInternal();
    }

    // ---- Internal ---------------------------------------------------------

    private static LogEntryBuilder log(String level, String source, String message, Exception ex, Id relatedRecordId) {
        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        // Always construct a builder so call sites can chain without a null check,
        // even when the entry is suspended/filtered and never actually buffered.
        if (suspended) {
            return new LogEntryBuilder(evt);
        }
        if (LogLevel.ordinalOf(level) < getMinLevel()) {
            return new LogEntryBuilder(evt); // below configured threshold — built but never buffered
        }

        evt.TransactionId__c         = getTransactionIdInternal();
        evt.ParentLogTransactionId__c = parentLogTransactionId;
        evt.Level__c                 = level;
        evt.Source__c                = source;
        evt.Message__c               = LogMasking.mask(message);
        evt.RelatedRecordId__c       = relatedRecordId;
        evt.OccurredAt__c            = System.now();
        evt.RunningUser__c           = UserInfo.getUserId();
        evt.Quiddity__c              = String.valueOf(Request.getCurrent().getQuiddity());

        if (ex != null) {
            evt.ExceptionType__c    = ex.getTypeName();
            evt.ExceptionMessage__c = LogMasking.mask(ex.getMessage());
            evt.StackTrace__c       = ex.getStackTraceString();
        }

        BUFFER.add(evt);

        // Safety net against unbounded heap growth in a runaway loop — NOT a
        // per-level auto-save. Still only fires a handful of times even in a
        // large loop, nowhere near the 150-calls-per-transaction ceiling,
        // since each save here batches everything buffered so far into one call.
        if (BUFFER.size() >= 200) {
            saveLog();
        }

        return new LogEntryBuilder(evt);
    }

    private static Integer getMinLevel() {
        if (minLevelOrdCache != null) {
            return minLevelOrdCache;
        }
        String levelName = LogLevelSettingSelector.getMinLevelForCurrentUser();
        minLevelOrdCache = LogLevel.ordinalOf(levelName);
        return minLevelOrdCache;
    }

    private static String getTransactionIdInternal() {
        if (transactionIdCache == null) {
            transactionIdCache = Request.getCurrent().getRequestId();
        }
        return transactionIdCache;
    }
}
