/**
 * Backs the relatedLogEntries LWC. Finds Log_Entry__c rows whose
 * RelatedRecordId__c matches the record the component is placed on — this is
 * a text-field match, not a true polymorphic lookup (Salesforce custom
 * objects can't declare one), so it's enforced here rather than by the
 * platform.
 */
public with sharing class RelatedLogEntriesController {

    public class EntrySummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String level;
        @AuraEnabled public String source;
        @AuraEnabled public String message;
        @AuraEnabled public String exceptionType;
        @AuraEnabled public DateTime occurredAt;
        @AuraEnabled public String logId;
    }

    @AuraEnabled(cacheable=true)
    public static List<EntrySummary> getRelatedEntries(Id recordId, Integer numRecords) {
        Integer safeLimit = (numRecords == null || numRecords <= 0) ? 20 : Math.min(numRecords, 100);

        List<EntrySummary> results = new List<EntrySummary>();
        for (Log_Entry__c entry : [
            SELECT Id, Level__c, Source__c, Message__c, ExceptionType__c, OccurredAt__c, Log__c
            FROM Log_Entry__c
            WHERE RelatedRecordId__c = :String.valueOf(recordId)
            ORDER BY OccurredAt__c DESC
            LIMIT :safeLimit
        ]) {
            EntrySummary summary = new EntrySummary();
            summary.id = entry.Id;
            summary.level = entry.Level__c;
            summary.source = entry.Source__c;
            summary.message = entry.Message__c;
            summary.exceptionType = entry.ExceptionType__c;
            summary.occurredAt = entry.OccurredAt__c;
            summary.logId = entry.Log__c;
            results.add(summary);
        }
        return results;
    }
}
