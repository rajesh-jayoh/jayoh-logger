/**
 * JayOh Logger — org-local logging utility.
 *
 * Usage:
 *   Logger.error('CBQuoteShippingAddressHandler.handle', 'Callout failed', ex);
 *   Logger.info('MyBatch.execute', 'Processed ' + records.size() + ' records');
 *   Logger.flush(); // call once, ideally in a `finally` block — see below
 *
 * Design notes:
 * - Entries are buffered in memory and published as Log_Entry_Event__e platform events
 *   ONLY when flush() is called. This mirrors Nebula Logger's model deliberately:
 *   EventBus.publish() calls are capped at 150 PER TRANSACTION (a hard Apex governor
 *   limit), but a single publish(list) call counts as ONE call no matter how many
 *   events are in the list — same as Database.insert(list) counting as one DML
 *   statement. Auto-flushing on every ERROR call (an earlier version of this class
 *   did this) means a loop that logs 200 errors makes 200 separate publish() calls
 *   and blows through that limit. Buffering everything and flushing once avoids that
 *   entirely — the trade-off is YOU must call flush(), ideally in a `finally` block,
 *   or a caught error that never reaches flush() is silently lost.
 * - Platform events also have a daily/hourly org-wide publish allocation (varies by
 *   edition — see Salesforce's Platform Event Limits). Batching reduces per-transaction
 *   risk but does not remove this org-wide ceiling; very high-volume orgs should
 *   monitor it (see Nebula Logger's own troubleshooting notes on this).
 * - setSyncMode(true) bypasses platform events entirely and inserts Log__c/Log_Entry__c
 *   directly and synchronously — useful for local debugging when you want to see the
 *   real DML error immediately, or if your org's platform event allocation is
 *   temporarily exhausted. Mirrors Nebula Logger's SYNCHRONOUS_DML save method.
 * - The minimum level to actually log is read once per transaction from
 *   Log_Level_Setting__mdt (see getMinLevel()), keyed by Profile/Permission Set.
 * - Simple field-name/value masking runs on message + context before persist.
 */
public without sharing class Logger {

    private static final List<Log_Entry_Event__e> BUFFER = new List<Log_Entry_Event__e>();
    private static Integer minLevelOrdCache = null;
    private static String transactionIdCache = null;
    private static Boolean suspended = false;
    private static Boolean syncMode = false;

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
     * Publish everything buffered so far as ONE EventBus.publish() call (or,
     * in sync mode, insert directly). This is the only method that actually
     * persists anything — nothing is saved until this (or an auto-flush at
     * the buffer size cap) runs.
     *
     * Recommended pattern, matching Nebula Logger's own guidance:
     *   try {
     *       // risky work, with Logger.error()/.warn()/.info() calls inside
     *   } finally {
     *       Logger.flush();
     *   }
     * A `finally` block runs even when an exception propagates past your
     * catch, so buffered entries still get published.
     */
    public static void flush() {
        if (BUFFER.isEmpty() || suspended) {
            return;
        }
        List<Log_Entry_Event__e> toPublish = BUFFER.deepClone();
        BUFFER.clear();

        if (syncMode) {
            LogEntryEventHandler.handle(toPublish); // direct, synchronous — see class comment
        } else {
            EventBus.publish(toPublish); // one call regardless of list size
        }
    }

    /**
     * Discards everything buffered so far WITHOUT publishing it. Mirrors
     * Nebula Logger's flushBuffer() — useful in tests, or when you've
     * decided mid-transaction that the buffered entries aren't worth keeping.
     */
    public static void flushBuffer() {
        BUFFER.clear();
    }

    /**
     * Ignores all log calls until resumeSaving() is called — they're simply
     * not buffered. Mirrors Nebula Logger's suspendSaving()/resumeSaving().
     * Useful for silencing noisy logging in a known-safe code path without
     * removing the call sites.
     */
    public static void suspendSaving() {
        suspended = true;
    }

    public static void resumeSaving() {
        suspended = false;
    }

    /**
     * When true, flush() bypasses platform events and inserts Log__c/Log_Entry__c
     * directly and synchronously. Mirrors Nebula Logger's SYNCHRONOUS_DML save
     * method — use for local debugging (you see the real DML error immediately
     * instead of a silently-dropped platform event) or as a fallback if your
     * org's platform event publish allocation is temporarily exhausted.
     * NOTE: in this mode, entries no longer survive a transaction rollback —
     * you lose the rollback-safety this framework exists for. Use sparingly.
     */
    public static void setSyncMode(Boolean isSync) {
        syncMode = isSync;
    }

    // ---- Internal ---------------------------------------------------------

    private static void log(String level, String source, String message, Exception ex, Id relatedRecordId) {
        if (suspended) {
            return;
        }
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

        // Safety net against unbounded heap growth in a runaway loop — NOT a
        // per-level auto-flush. This still only fires (at most) a handful of
        // times even in a large loop, nowhere near the 150-calls-per-transaction
        // ceiling, since each flush here batches everything buffered so far
        // into a single publish() call.
        if (BUFFER.size() >= 200) {
            flush();
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
