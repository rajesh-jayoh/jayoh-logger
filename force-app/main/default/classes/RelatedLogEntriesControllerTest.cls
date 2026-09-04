@isTest
private class RelatedLogEntriesControllerTest {

    @testSetup
    static void setup() {
        Account acct = new Account(Name = 'Related Entries Test Account');
        insert acct;

        Log__c log = new Log__c(TransactionId__c = 'RELATED-TXN', HighestSeverity__c = 'ERROR');
        insert log;

        insert new List<Log_Entry__c>{
            new Log_Entry__c(
                Log__c = log.Id, Level__c = 'ERROR', Source__c = 'x', Message__c = 'failed for this account',
                RelatedRecordId__c = acct.Id, OccurredAt__c = System.now()
            ),
            new Log_Entry__c(
                Log__c = log.Id, Level__c = 'INFO', Source__c = 'y', Message__c = 'unrelated entry',
                RelatedRecordId__c = null, OccurredAt__c = System.now()
            )
        };
    }

    @isTest
    static void testGetRelatedEntriesFiltersToMatchingRecord() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Related Entries Test Account'];

        Test.startTest();
        List<RelatedLogEntriesController.EntrySummary> results = RelatedLogEntriesController.getRelatedEntries(acct.Id, 20);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('failed for this account', results[0].message);
    }

    @isTest
    static void testGetRelatedEntriesReturnsEmptyForUnrelatedRecord() {
        Account otherAcct = new Account(Name = 'No Logs Account');
        insert otherAcct;

        Test.startTest();
        List<RelatedLogEntriesController.EntrySummary> results = RelatedLogEntriesController.getRelatedEntries(otherAcct.Id, 20);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testDefaultAndCappedLimitDoNotThrow() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Related Entries Test Account'];

        Test.startTest();
        List<RelatedLogEntriesController.EntrySummary> defaultLimit = RelatedLogEntriesController.getRelatedEntries(acct.Id, null);
        List<RelatedLogEntriesController.EntrySummary> cappedLimit = RelatedLogEntriesController.getRelatedEntries(acct.Id, 9999);
        Test.stopTest();

        System.assert(defaultLimit != null);
        System.assert(cappedLimit != null);
    }
}
