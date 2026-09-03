/**
 * JayOh Logger — org-local logging utility.
 *
 * Usage:
 *   Logger.error('CBQuoteShippingAddressHandler.handle', 'Callout failed', ex);
 *   Logger.info('MyBatch.execute', 'Processed ' + records.size() + ' records');
 *   Logger.flush();   // call at the end of the transaction (or rely on finish() in async contexts)
 *
 * Design notes:
 * - Entries are buffered in memory and published as Log_Entry_Event__e platform events.
 *   Platform events commit independently of the surrounding transaction, so an entry
 *   logged right before a DML exception or callout failure is NOT lost when the
 *   transaction rolls back — this is the main reason to use platform events instead
 *   of direct DML on Log_Entry__c.
 * - The minimum level to actually publish is read once per transaction from
 *   Log_Level_Setting__mdt (see getMinLevel()), keyed by Profile/Permission Set.
 * - Simple field-name/value masking runs on message + context before publish.
 */
public without sharing class Logger {

    private static final List<Log_Entry_Event__e> BUFFER = new List<Log_Entry_Event__e>();
    private static Integer minLevelOrdCache = null;
    private static String transactionIdCache = null;

    // ---- Public API -----------------------------------------------------

    public static void error(String source, String message) {
        log('ERROR', source, message, null, null);
    }

    public static void error(String source, String message, Exception ex) {
        log('ERROR', source, message, ex, null);
    }

    public static void warn(String source, String message) {
        log('WARN', source, message, null, null);
    }

    public static void info(String source, String message) {
        log('INFO', source, message, null, null);
    }

    public static void debug(String source, String message) {
        log('DEBUG', source, message, null, null);
    }

    /** Attach a related record Id (polymorphic — stored as text) to the next-buffered call sites manually if needed. */
    public static void error(String source, String message, Exception ex, Id relatedRecordId) {
        log('ERROR', source, message, ex, relatedRecordId);
    }

    /**
     * Publish everything buffered so far. Safe to call multiple times; the
     * buffer is cleared after each flush. Call this explicitly at natural
     * checkpoints (end of a batch execute(), before a risky callout, etc.)
     * rather than relying only on end-of-transaction behavior.
     */
    public static void flush() {
        if (BUFFER.isEmpty()) {
            return;
        }
        List<Log_Entry_Event__e> toPublish = BUFFER.deepClone();
        BUFFER.clear();
        EventBus.publish(toPublish);
    }

    // ---- Internal ---------------------------------------------------------

    private static void log(String level, String source, String message, Exception ex, Id relatedRecordId) {
        if (LogLevel.ordinalOf(level) < getMinLevel()) {
            return; // below configured threshold for this user's Profile/Permission Set
        }

        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        evt.TransactionId__c   = getTransactionId();
        evt.Level__c           = level;
        evt.Source__c          = source;
        evt.Message__c         = LogMasking.mask(message);
        evt.RelatedRecordId__c = relatedRecordId;
        evt.OccurredAt__c      = System.now();
        evt.RunningUser__c     = UserInfo.getUserId();
        evt.Quiddity__c        = String.valueOf(Request.getCurrent().getQuiddity());

        if (ex != null) {
            evt.ExceptionType__c    = ex.getTypeName();
            evt.ExceptionMessage__c = LogMasking.mask(ex.getMessage());
            evt.StackTrace__c       = ex.getStackTraceString();
        }

        BUFFER.add(evt);

        // Cap buffer growth so a runaway loop can't itself become a limits problem.
        if (BUFFER.size() >= 50) {
            flush();
        }

        if (level == 'ERROR') {
            flush(); // errors are worth persisting immediately rather than risking a later rollback losing them
        }
    }

    private static Integer getMinLevel() {
        if (minLevelOrdCache != null) {
            return minLevelOrdCache;
        }
        String levelName = LogLevelSettingSelector.getMinLevelForCurrentUser();
        minLevelOrdCache = LogLevel.ordinalOf(levelName);
        return minLevelOrdCache;
    }

    private static String getTransactionId() {
        if (transactionIdCache == null) {
            transactionIdCache = Request.getCurrent().getRequestId();
        }
        return transactionIdCache;
    }
}
