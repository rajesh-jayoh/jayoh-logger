/**
 * Persists Log_Entry_Event__e platform events into durable Log__c (header,
 * one per transaction id) and Log_Entry__c (child, one per log call).
 *
 * Idempotency: upserts Log__c on TransactionId__c (external-id-style unique
 * field) so multiple flushes within the same transaction, or the same
 * transaction id appearing across an async retry, don't create duplicate headers.
 */
public without sharing class LogEntryEventHandler {

    public static void handle(List<Log_Entry_Event__e> events) {
        if (events.isEmpty()) {
            return;
        }

        Map<String, Log__c> headersByTxnId = new Map<String, Log__c>();
        for (Log_Entry_Event__e e : events) {
            if (!headersByTxnId.containsKey(e.TransactionId__c)) {
                headersByTxnId.put(e.TransactionId__c, new Log__c(
                    TransactionId__c = e.TransactionId__c,
                    HighestSeverity__c = e.Level__c
                ));
            } else {
                Log__c existing = headersByTxnId.get(e.TransactionId__c);
                if (LogLevel.ordinalOf(e.Level__c) > LogLevel.ordinalOf(existing.HighestSeverity__c)) {
                    existing.HighestSeverity__c = e.Level__c;
                }
            }
        }

        // Merge with any already-persisted header for the same transaction id
        // (e.g. a second flush() call later in the same request).
        Map<String, Log__c> existingHeaders = new Map<String, Log__c>();
        for (Log__c l : [
            SELECT Id, TransactionId__c, HighestSeverity__c
            FROM Log__c
            WHERE TransactionId__c IN :headersByTxnId.keySet()
        ]) {
            existingHeaders.put(l.TransactionId__c, l);
        }
        for (String txnId : headersByTxnId.keySet()) {
            if (existingHeaders.containsKey(txnId)) {
                Log__c existing = existingHeaders.get(txnId);
                Log__c incoming = headersByTxnId.get(txnId);
                if (LogLevel.ordinalOf(incoming.HighestSeverity__c) > LogLevel.ordinalOf(existing.HighestSeverity__c)) {
                    existing.HighestSeverity__c = incoming.HighestSeverity__c;
                }
                headersByTxnId.put(txnId, existing);
            }
        }

        upsert headersByTxnId.values() TransactionId__c;

        // Re-map by id now that headers are saved
        Map<String, Id> headerIdByTxnId = new Map<String, Id>();
        for (Log__c l : headersByTxnId.values()) {
            headerIdByTxnId.put(l.TransactionId__c, l.Id);
        }

        List<Log_Entry__c> entries = new List<Log_Entry__c>();
        for (Log_Entry_Event__e e : events) {
            entries.add(new Log_Entry__c(
                Log__c              = headerIdByTxnId.get(e.TransactionId__c),
                Level__c             = e.Level__c,
                Source__c            = e.Source__c,
                Message__c           = e.Message__c,
                ExceptionType__c     = e.ExceptionType__c,
                ExceptionMessage__c  = e.ExceptionMessage__c,
                StackTrace__c        = e.StackTrace__c,
                RelatedRecordId__c   = e.RelatedRecordId__c,
                OccurredAt__c        = e.OccurredAt__c,
                RunningUser__c       = e.RunningUser__c,
                Quiddity__c          = e.Quiddity__c
            ));
        }
        insert entries;

        List<Log_Entry__c> errorEntries = new List<Log_Entry__c>();
        for (Log_Entry__c e : entries) {
            if (e.Level__c == 'ERROR') {
                errorEntries.add(e);
            }
        }
        if (!errorEntries.isEmpty()) {
            LogAlertService.notifyOnErrors(errorEntries);
        }
    }
}
