@isTest
private class LogPurgeBatchTest {

    @isTest
    static void testPurgesRecordsOlderThanRetention() {
        Log__c oldLog = new Log__c(TransactionId__c = 'OLD-TXN', HighestSeverity__c = 'INFO');
        Log__c recentLog = new Log__c(TransactionId__c = 'RECENT-TXN', HighestSeverity__c = 'INFO');
        insert new List<Log__c>{ oldLog, recentLog };

        // Default retention is 30 days (see shipped 'Default' CMDT record) —
        // backdate one record well past that, leave the other fresh.
        Test.setCreatedDate(oldLog.Id, DateTime.now().addDays(-45));

        Test.startTest();
        Database.executeBatch(new LogPurgeBatch());
        Test.stopTest();

        List<Log__c> remaining = [SELECT Id, TransactionId__c FROM Log__c];
        System.assertEquals(1, remaining.size());
        System.assertEquals('RECENT-TXN', remaining[0].TransactionId__c);
    }

    @isTest
    static void testSchedulableKicksOffBatch() {
        Test.startTest();
        String jobId = System.schedule(
            'JayOh Log Purge Test',
            '0 0 2 * * ?',
            new LogPurgeBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    @isTest
    static void testExportBeforePurgeSendsEmailThenDeletes() {
        LogPurgeBatch.mockDefaultSetting = new Log_Level_Setting__mdt(
            RetentionDays__c = 30,
            ExportBeforePurge__c = true,
            ExportRecipientEmail__c = 'archive@example.com'
        );

        Log__c oldLog = new Log__c(TransactionId__c = 'EXPORT-TXN', HighestSeverity__c = 'ERROR');
        insert oldLog;
        insert new Log_Entry__c(Log__c = oldLog.Id, Level__c = 'ERROR', Source__c = 'x', Message__c = 'failed');
        Test.setCreatedDate(oldLog.Id, DateTime.now().addDays(-45));

        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        Database.executeBatch(new LogPurgeBatch());
        Test.stopTest();

        System.assert(Limits.getEmailInvocations() > emailsBefore, 'Expected an export email before the purge deletes records');
        System.assertEquals(0, [SELECT COUNT() FROM Log__c WHERE TransactionId__c = 'EXPORT-TXN']);
    }

    @isTest
    static void testExportDisabledSkipsEmailButStillPurges() {
        LogPurgeBatch.mockDefaultSetting = new Log_Level_Setting__mdt(
            RetentionDays__c = 30,
            ExportBeforePurge__c = false
        );

        Log__c oldLog = new Log__c(TransactionId__c = 'NOEXPORT-TXN', HighestSeverity__c = 'INFO');
        insert oldLog;
        Test.setCreatedDate(oldLog.Id, DateTime.now().addDays(-45));

        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        Database.executeBatch(new LogPurgeBatch());
        Test.stopTest();

        System.assertEquals(emailsBefore, Limits.getEmailInvocations(), 'No export email should be sent when disabled');
        System.assertEquals(0, [SELECT COUNT() FROM Log__c WHERE TransactionId__c = 'NOEXPORT-TXN']);
    }
}
