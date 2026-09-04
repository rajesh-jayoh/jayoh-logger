@isTest
private class LoggerFlowActionsTest {

    @isTest
    static void testLogMessageActionBuffersButDoesNotSave() {
        LoggerFlowLogMessageAction.Request req = new LoggerFlowLogMessageAction.Request();
        req.level = 'ERROR';
        req.source = 'Flow: Renewal_Closed_Won';
        req.message = 'Slack notification failed';
        req.tags = 'chargebee, renewal';

        Test.startTest();
        LoggerFlowLogMessageAction.execute(new List<LoggerFlowLogMessageAction.Request>{ req });
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c WHERE Source__c = 'Flow: Renewal_Closed_Won'
        ];
        System.assertEquals(0, entries.size(), 'Log Message action should buffer only — nothing persists without a Save Log action');
    }

    @isTest
    static void testLogMessageThenSaveLogPersistsWithTags() {
        LoggerFlowLogMessageAction.Request req = new LoggerFlowLogMessageAction.Request();
        req.level = 'ERROR';
        req.source = 'Flow: Renewal_Closed_Won';
        req.message = 'Slack notification failed';
        req.tags = 'chargebee, renewal';

        Test.startTest();
        LoggerFlowLogMessageAction.execute(new List<LoggerFlowLogMessageAction.Request>{ req });
        LoggerFlowSaveLogAction.execute();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c, Tags__c FROM Log_Entry__c WHERE Source__c = 'Flow: Renewal_Closed_Won'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('ERROR', entries[0].Level__c);
        System.assert(entries[0].Tags__c.contains('chargebee'));
        System.assert(entries[0].Tags__c.contains('renewal'));
    }

    @isTest
    static void testLogEntryForRecordActionSetsRelatedRecordId() {
        Account acct = new Account(Name = 'Flow Record Action Test');
        insert acct;

        LoggerFlowLogRecordAction.Request req = new LoggerFlowLogRecordAction.Request();
        req.level = 'WARN';
        req.source = 'Flow: AccountValidation';
        req.message = 'Validation warning';
        req.record = acct;

        Test.startTest();
        LoggerFlowLogRecordAction.execute(new List<LoggerFlowLogRecordAction.Request>{ req });
        LoggerFlowSaveLogAction.execute();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT RelatedRecordId__c FROM Log_Entry__c WHERE Source__c = 'Flow: AccountValidation'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals(acct.Id, (Id) entries[0].RelatedRecordId__c);
    }

    @isTest
    static void testLogEntryForRecordCollectionCreatesOneEntryPerRecord() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Collection Test 1'),
            new Account(Name = 'Collection Test 2'),
            new Account(Name = 'Collection Test 3')
        };
        insert accounts;

        LoggerFlowLogRecordCollectionAction.Request req = new LoggerFlowLogRecordCollectionAction.Request();
        req.level = 'INFO';
        req.source = 'Flow: BulkAccountProcessor';
        req.message = 'Processed in this run';
        req.records = accounts;

        Test.startTest();
        LoggerFlowLogRecordCollectionAction.execute(new List<LoggerFlowLogRecordCollectionAction.Request>{ req });
        LoggerFlowSaveLogAction.execute();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT RelatedRecordId__c FROM Log_Entry__c WHERE Source__c = 'Flow: BulkAccountProcessor'
        ];
        System.assertEquals(3, entries.size(), 'One entry per record in the collection');
    }

    @isTest
    static void testLogEntryForRecordCollectionHandlesNullListWithoutThrowing() {
        LoggerFlowLogRecordCollectionAction.Request req = new LoggerFlowLogRecordCollectionAction.Request();
        req.level = 'INFO';
        req.source = 'Flow: EdgeCase';
        req.message = 'no records';
        req.records = null;

        Test.startTest();
        LoggerFlowLogRecordCollectionAction.execute(new List<LoggerFlowLogRecordCollectionAction.Request>{ req });
        LoggerFlowSaveLogAction.execute();
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testSaveLogActionWithEmptyBufferDoesNotThrow() {
        Test.startTest();
        LoggerFlowSaveLogAction.execute(); // nothing buffered
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testClientLogPersistsWithSingleFlush() {
        Test.startTest();
        LoggerClientInvocable.logFromClient('WARN', 'LWC: quoteShippingAddress', 'Validation warning', null);
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c FROM Log_Entry__c
            WHERE Source__c = 'LWC: quoteShippingAddress'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('WARN', entries[0].Level__c);
    }

    @isTest
    static void testClientLogUnknownLevelDefaultsToInfo() {
        Test.startTest();
        LoggerClientInvocable.logFromClient('NOT_A_LEVEL', 'LWC: testComponent', 'edge case', null);
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c FROM Log_Entry__c
            WHERE Source__c = 'LWC: testComponent'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('INFO', entries[0].Level__c);
    }
}
