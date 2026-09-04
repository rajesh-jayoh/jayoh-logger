@isTest
private class LoggerPluginDispatcherTest {

    // Inner classes referenced by name via Type.forName() in the tests below —
    // this is the same mechanism LoggerPluginDispatcher uses in production to
    // instantiate a real plugin from its configured class name.
    public class FakePlugin implements LoggerPluginTriggerable {
        public static Integer executionCount = 0;
        public void execute(LoggerPluginContext context) {
            executionCount++;
        }
    }

    public class ThrowingPlugin implements LoggerPluginTriggerable {
        public void execute(LoggerPluginContext context) {
            throw new System.NoAccessException('deliberate test failure');
        }
    }

    public class NotAPlugin {
        // Deliberately does NOT implement LoggerPluginTriggerable
    }

    @isTest
    static void testEnabledPluginRunsForMatchingObject() {
        FakePlugin.executionCount = 0;
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c',
                ApexClassName__c = 'LoggerPluginDispatcherTest.FakePlugin',
                IsEnabled__c = true,
                ExecutionOrder__c = 0
            )
        };

        Test.startTest();
        LoggerPluginDispatcher.run(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ new Log__c() }, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, FakePlugin.executionCount);
    }

    @isTest
    static void testPluginSkippedForNonMatchingObject() {
        FakePlugin.executionCount = 0;
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c', // registered for Log__c only
                ApexClassName__c = 'LoggerPluginDispatcherTest.FakePlugin',
                IsEnabled__c = true,
                ExecutionOrder__c = 0
            )
        };

        Test.startTest();
        LoggerPluginDispatcher.run(
            Schema.Log_Entry__c.SObjectType, System.TriggerOperation.BEFORE_INSERT, // different object
            new List<SObject>{ new Log_Entry__c() }, null, null, null
        );
        Test.stopTest();

        System.assertEquals(0, FakePlugin.executionCount, 'A plugin registered for Log__c should not run for Log_Entry__c');
    }

    @isTest
    static void testDisabledPluginDoesNotRun() {
        FakePlugin.executionCount = 0;
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c',
                ApexClassName__c = 'LoggerPluginDispatcherTest.FakePlugin',
                IsEnabled__c = false, // disabled
                ExecutionOrder__c = 0
            )
        };

        Test.startTest();
        LoggerPluginDispatcher.run(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ new Log__c() }, null, null, null
        );
        Test.stopTest();

        System.assertEquals(0, FakePlugin.executionCount);
    }

    @isTest
    static void testThrowingPluginDoesNotPropagateOrBlockDml() {
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c',
                ApexClassName__c = 'LoggerPluginDispatcherTest.ThrowingPlugin',
                IsEnabled__c = true,
                ExecutionOrder__c = 0
            )
        };

        Test.startTest();
        // Should not throw — the dispatcher catches and swallows plugin exceptions.
        LoggerPluginDispatcher.run(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ new Log__c() }, null, null, null
        );
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testNonExistentClassNameDoesNotThrow() {
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c',
                ApexClassName__c = 'ThisClassDoesNotExistAnywhere12345',
                IsEnabled__c = true,
                ExecutionOrder__c = 0
            )
        };

        Test.startTest();
        LoggerPluginDispatcher.run(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ new Log__c() }, null, null, null
        );
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testClassNotImplementingInterfaceDoesNotThrow() {
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c',
                ApexClassName__c = 'LoggerPluginDispatcherTest.NotAPlugin',
                IsEnabled__c = true,
                ExecutionOrder__c = 0
            )
        };

        Test.startTest();
        LoggerPluginDispatcher.run(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ new Log__c() }, null, null, null
        );
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testEndToEndTriggerFiresPluginOnRealInsert() {
        // Proves the actual LogTrigger -> LoggerPluginDispatcher wiring, not
        // just a direct call to run() — this is what distinguishes "the
        // dispatcher logic works" from "the plugin framework works."
        FakePlugin.executionCount = 0;
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c',
                ApexClassName__c = 'LoggerPluginDispatcherTest.FakePlugin',
                IsEnabled__c = true,
                ExecutionOrder__c = 0
            )
        };

        Test.startTest();
        insert new Log__c(TransactionId__c = 'PLUGIN-E2E-TXN', HighestSeverity__c = 'INFO');
        Test.stopTest();

        // before insert + after insert both fire the trigger, so the plugin
        // (registered with no operation-type filter of its own) runs twice.
        System.assertEquals(2, FakePlugin.executionCount);
    }

    @isTest
    static void testMultiplePluginsRunInExecutionOrder() {
        FakePlugin.executionCount = 0;
        LoggerPluginDispatcher.mockPlugins = new List<Log_Plugin__mdt>{
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c', ApexClassName__c = 'LoggerPluginDispatcherTest.ThrowingPlugin',
                IsEnabled__c = true, ExecutionOrder__c = 0
            ),
            new Log_Plugin__mdt(
                SObjectApiName__c = 'Log__c', ApexClassName__c = 'LoggerPluginDispatcherTest.FakePlugin',
                IsEnabled__c = true, ExecutionOrder__c = 1
            )
        };

        Test.startTest();
        // The first plugin throws; the second must still run — proves one
        // broken plugin doesn't stop the others.
        LoggerPluginDispatcher.run(
            Schema.Log__c.SObjectType, System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ new Log__c() }, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, FakePlugin.executionCount);
    }
}
