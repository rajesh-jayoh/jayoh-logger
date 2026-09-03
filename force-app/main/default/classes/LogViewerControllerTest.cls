@isTest
private class LogViewerControllerTest {

    @testSetup
    static void setup() {
        Log__c log1 = new Log__c(TransactionId__c = 'VIEW-TXN-1', HighestSeverity__c = 'ERROR');
        Log__c log2 = new Log__c(TransactionId__c = 'VIEW-TXN-2', HighestSeverity__c = 'INFO');
        insert new List<Log__c>{ log1, log2 };

        insert new List<Log_Entry__c>{
            new Log_Entry__c(Log__c = log1.Id, Level__c = 'ERROR', Source__c = 'x', Message__c = 'failed', OccurredAt__c = System.now()),
            new Log_Entry__c(Log__c = log2.Id, Level__c = 'INFO', Source__c = 'y', Message__c = 'ok', OccurredAt__c = System.now())
        };
    }

    @isTest
    static void testGetRecentLogsReturnsAll() {
        Test.startTest();
        List<LogViewerController.LogSummary> results = LogViewerController.getRecentLogs(25, 'ALL');
        Test.stopTest();

        System.assertEquals(2, results.size());
    }

    @isTest
    static void testGetRecentLogsFiltersBySeverity() {
        Test.startTest();
        List<LogViewerController.LogSummary> results = LogViewerController.getRecentLogs(25, 'ERROR');
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('ERROR', results[0].highestSeverity);
    }

    @isTest
    static void testGetRecentLogsDefaultsAndCapsLimit() {
        Test.startTest();
        List<LogViewerController.LogSummary> defaultLimit = LogViewerController.getRecentLogs(null, 'ALL');
        List<LogViewerController.LogSummary> cappedLimit = LogViewerController.getRecentLogs(9999, 'ALL');
        Test.stopTest();

        System.assert(defaultLimit != null);
        System.assert(cappedLimit != null);
    }

    @isTest
    static void testGetLogEntriesReturnsChildren() {
        Log__c log1 = [SELECT Id FROM Log__c WHERE TransactionId__c = 'VIEW-TXN-1'];

        Test.startTest();
        List<LogViewerController.EntryDetail> entries = LogViewerController.getLogEntries(log1.Id);
        Test.stopTest();

        System.assertEquals(1, entries.size());
        System.assertEquals('ERROR', entries[0].level);
    }
}
