@isTest
private class LoggerPluginExampleSetPriorityTest {

    @isTest
    static void testEscalatesPriorityToCriticalForErrorSeverity() {
        Log__c log = new Log__c(HighestSeverity__c = 'ERROR', Priority__c = 'Medium');
        LoggerPluginContext context = new LoggerPluginContext(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ log }, null, null, null
        );

        Test.startTest();
        new LoggerPluginExampleSetPriority().execute(context);
        Test.stopTest();

        System.assertEquals('Critical', log.Priority__c);
    }

    @isTest
    static void testLeavesNonErrorSeverityUnchanged() {
        Log__c log = new Log__c(HighestSeverity__c = 'INFO', Priority__c = 'Low');
        LoggerPluginContext context = new LoggerPluginContext(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ log }, null, null, null
        );

        Test.startTest();
        new LoggerPluginExampleSetPriority().execute(context);
        Test.stopTest();

        System.assertEquals('Low', log.Priority__c);
    }

    @isTest
    static void testIgnoresNonLogSObjectType() {
        Log_Entry__c entry = new Log_Entry__c();
        LoggerPluginContext context = new LoggerPluginContext(
            Schema.Log_Entry__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ entry }, null, null, null
        );

        Test.startTest();
        new LoggerPluginExampleSetPriority().execute(context); // should return immediately, no error
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testIgnoresAfterInsertOperation() {
        Log__c log = new Log__c(HighestSeverity__c = 'ERROR', Priority__c = 'Medium');
        LoggerPluginContext context = new LoggerPluginContext(
            Schema.Log__c.SObjectType, System.TriggerOperation.AFTER_INSERT, // not a before-context
            new List<SObject>{ log }, null, null, null
        );

        Test.startTest();
        new LoggerPluginExampleSetPriority().execute(context);
        Test.stopTest();

        System.assertEquals('Medium', log.Priority__c, 'Field updates only make sense in a before-context; AFTER_INSERT should be a no-op');
    }
}
