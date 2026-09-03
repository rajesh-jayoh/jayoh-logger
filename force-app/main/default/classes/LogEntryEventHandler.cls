/**
 * Persists Log_Entry_Event__e platform events into durable Log__c (header,
 * one per transaction id), Log_Entry__c (child, one per log call), and
 * Log_Tag__c/Log_Entry_Tag__c (normalized tags, if any were set via
 * LogEntryBuilder.addTag()/addTags()).
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
        Map<String, String> parentTxnIdByTxnId = new Map<String, String>();
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
            if (String.isNotBlank(e.ParentLogTransactionId__c)) {
                parentTxnIdByTxnId.put(e.TransactionId__c, e.ParentLogTransactionId__c);
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

        // Resolve parent Log__c lookups where a matching parent transaction has
        // already been persisted. If the parent hasn't been saved yet (e.g. it's
        // still buffered, unflushed, in the calling transaction), this silently
        // leaves ParentLog__c blank rather than failing the whole save.
        if (!parentTxnIdByTxnId.isEmpty()) {
            Map<String, Id> parentHeaderIdByTxnId = new Map<String, Id>();
            for (Log__c parentLog : [
                SELECT Id, TransactionId__c FROM Log__c WHERE TransactionId__c IN :parentTxnIdByTxnId.values()
            ]) {
                parentHeaderIdByTxnId.put(parentLog.TransactionId__c, parentLog.Id);
            }
            for (String txnId : parentTxnIdByTxnId.keySet()) {
                Id parentId = parentHeaderIdByTxnId.get(parentTxnIdByTxnId.get(txnId));
                if (parentId != null) {
                    headersByTxnId.get(txnId).ParentLog__c = parentId;
                }
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
                Quiddity__c          = e.Quiddity__c,
                Tags__c              = e.Tags__c
            ));
        }
        insert entries;

        persistTags(entries);

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

    /**
     * Splits each entry's semicolon-separated Tags__c into normalized
     * Log_Tag__c records (deduped by Name, reused across entries) and
     * Log_Entry_Tag__c junction rows.
     */
    private static void persistTags(List<Log_Entry__c> entries) {
        Set<String> allTagNames = new Set<String>();
        Map<Id, List<String>> tagNamesByEntryId = new Map<Id, List<String>>();

        for (Log_Entry__c entry : entries) {
            if (String.isBlank(entry.Tags__c)) {
                continue;
            }
            List<String> tagNames = new List<String>();
            for (String rawTag : entry.Tags__c.split(';')) {
                String tagName = rawTag.trim();
                if (String.isNotBlank(tagName)) {
                    tagNames.add(tagName);
                    allTagNames.add(tagName);
                }
            }
            if (!tagNames.isEmpty()) {
                tagNamesByEntryId.put(entry.Id, tagNames);
            }
        }

        if (allTagNames.isEmpty()) {
            return;
        }

        Map<String, Log_Tag__c> tagsByName = new Map<String, Log_Tag__c>();
        for (Log_Tag__c existingTag : [SELECT Id, Name FROM Log_Tag__c WHERE Name IN :allTagNames]) {
            tagsByName.put(existingTag.Name, existingTag);
        }

        List<Log_Tag__c> newTags = new List<Log_Tag__c>();
        for (String tagName : allTagNames) {
            if (!tagsByName.containsKey(tagName)) {
                newTags.add(new Log_Tag__c(Name = tagName));
            }
        }
        if (!newTags.isEmpty()) {
            insert newTags;
            for (Log_Tag__c newTag : newTags) {
                tagsByName.put(newTag.Name, newTag);
            }
        }

        List<Log_Entry_Tag__c> junctions = new List<Log_Entry_Tag__c>();
        for (Id entryId : tagNamesByEntryId.keySet()) {
            for (String tagName : tagNamesByEntryId.get(entryId)) {
                junctions.add(new Log_Entry_Tag__c(
                    Log_Entry__c = entryId,
                    Log_Tag__c = tagsByName.get(tagName).Id
                ));
            }
        }
        if (!junctions.isEmpty()) {
            insert junctions;
        }
    }
}
