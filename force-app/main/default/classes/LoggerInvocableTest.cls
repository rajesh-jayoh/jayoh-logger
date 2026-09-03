@isTest
private class LoggerInvocableTest {

    @isTest
    static void testLogFromFlowPersistsEntry() {
        LoggerInvocable.LogRequest req = new LoggerInvocable.LogRequest();
        req.level = 'ERROR';
        req.source = 'Flow: Renewal_Closed_Won';
        req.message = 'Slack notification failed';

        Test.startTest();
        LoggerInvocable.logFromFlow(new List<LoggerInvocable.LogRequest>{ req });
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c, Message__c FROM Log_Entry__c
            WHERE Source__c = 'Flow: Renewal_Closed_Won'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('ERROR', entries[0].Level__c);
    }

    @isTest
    static void testLogFromClientPersistsEntry() {
        Test.startTest();
        LoggerInvocable.logFromClient('WARN', 'LWC: quoteShippingAddress', 'Validation warning', null);
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
    static void testUnknownLevelDefaultsToInfo() {
        Test.startTest();
        LoggerInvocable.logFromClient('NOT_A_LEVEL', 'LWC: testComponent', 'edge case', null);
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
