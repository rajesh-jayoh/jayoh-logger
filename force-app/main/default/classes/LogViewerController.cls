/**
 * Read-only controller backing the logViewer LWC. Deliberately simple —
 * no filters beyond level and a row limit — since the viewer is meant for
 * a quick "what broke recently" glance, not a full report builder.
 */
public with sharing class LogViewerController {

    public class LogSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String transactionId;
        @AuraEnabled public String highestSeverity;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Integer entryCount;
    }

    public class EntryDetail {
        @AuraEnabled public String level;
        @AuraEnabled public String source;
        @AuraEnabled public String message;
        @AuraEnabled public String exceptionType;
        @AuraEnabled public String exceptionMessage;
        @AuraEnabled public String stackTrace;
        @AuraEnabled public String quiddity;
        @AuraEnabled public DateTime occurredAt;
    }

    @AuraEnabled(cacheable=true)
    public static List<LogSummary> getRecentLogs(Integer numRecords, String levelFilter) {
        Integer safeLimit = (numRecords == null || numRecords <= 0) ? 25 : Math.min(numRecords, 200);

        String query = 'SELECT Id, TransactionId__c, HighestSeverity__c, CreatedDate, ' +
                       '(SELECT Id FROM Log_Entries__r) FROM Log__c';
        List<String> conditions = new List<String>();
        if (String.isNotBlank(levelFilter) && levelFilter != 'ALL') {
            conditions.add('HighestSeverity__c = :levelFilter');
        }
        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }
        query += ' ORDER BY CreatedDate DESC LIMIT :safeLimit';

        List<Log__c> logs = Database.query(query);

        List<LogSummary> results = new List<LogSummary>();
        for (Log__c log : logs) {
            LogSummary summary = new LogSummary();
            summary.id = log.Id;
            summary.transactionId = log.TransactionId__c;
            summary.highestSeverity = log.HighestSeverity__c;
            summary.createdDate = log.CreatedDate;
            summary.entryCount = log.Log_Entries__r.size();
            results.add(summary);
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<EntryDetail> getLogEntries(Id logId) {
        List<EntryDetail> results = new List<EntryDetail>();
        for (Log_Entry__c entry : [
            SELECT Level__c, Source__c, Message__c, ExceptionType__c,
                   ExceptionMessage__c, StackTrace__c, Quiddity__c, OccurredAt__c
            FROM Log_Entry__c
            WHERE Log__c = :logId
            ORDER BY OccurredAt__c ASC
        ]) {
            EntryDetail d = new EntryDetail();
            d.level = entry.Level__c;
            d.source = entry.Source__c;
            d.message = entry.Message__c;
            d.exceptionType = entry.ExceptionType__c;
            d.exceptionMessage = entry.ExceptionMessage__c;
            d.stackTrace = entry.StackTrace__c;
            d.quiddity = entry.Quiddity__c;
            d.occurredAt = entry.OccurredAt__c;
            results.add(d);
        }
        return results;
    }
}
