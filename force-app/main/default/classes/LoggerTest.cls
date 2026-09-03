@isTest
private class LoggerTest {

    @isTest
    static void testErrorLogAutoFlushesAndPersists() {
        Test.startTest();
        Logger.error('LoggerTest.testErrorLogAutoFlushesAndPersists', 'Boom', new DmlException('bad'));
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c, Source__c, ExceptionType__c
            FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testErrorLogAutoFlushesAndPersists'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('ERROR', entries[0].Level__c);
        System.assertEquals('System.DmlException', entries[0].ExceptionType__c);
    }

    @isTest
    static void testInfoLogRequiresExplicitFlush() {
        Test.startTest();
        Logger.info('LoggerTest.testInfoLogRequiresExplicitFlush', 'just fyi');
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testInfoLogRequiresExplicitFlush'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('INFO', entries[0].Level__c);
    }

    @isTest
    static void testDebugBelowDefaultThresholdIsSuppressed() {
        // Default CMDT record ships with MinimumLevel__c = INFO, so DEBUG
        // calls should be filtered out and never reach the platform event bus.
        Test.startTest();
        Logger.debug('LoggerTest.testDebugBelowDefaultThresholdIsSuppressed', 'should not persist');
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testDebugBelowDefaultThresholdIsSuppressed'
        ];
        System.assertEquals(0, entries.size(), 'DEBUG entries should be suppressed under the default INFO threshold');
    }

    @isTest
    static void testFlushWithEmptyBufferDoesNotThrow() {
        Test.startTest();
        Logger.flush(); // nothing buffered
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testMessageIsMaskedBeforePersist() {
        Test.startTest();
        Logger.error('LoggerTest.testMessageIsMaskedBeforePersist', 'card 4111111111111111 declined');
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Message__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testMessageIsMaskedBeforePersist'
        ];
        System.assertEquals(1, entries.size());
        System.assert(!entries[0].Message__c.contains('4111111111111111'));
    }

    @isTest
    static void testBulkLoggingTriggersAutoFlushAtBufferCap() {
        // Buffer caps at 50 and auto-flushes; 120 INFO calls should trigger
        // multiple internal flush()es without the caller doing anything special,
        // and every entry should still make it through the trigger to Log_Entry__c.
        Test.startTest();
        for (Integer i = 0; i < 120; i++) {
            Logger.info('LoggerTest.testBulkLoggingTriggersAutoFlushAtBufferCap', 'entry ' + i);
        }
        Logger.flush(); // flush whatever remains under the cap
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testBulkLoggingTriggersAutoFlushAtBufferCap'
        ];
        System.assertEquals(120, entries.size(), 'All 120 buffered entries should persist across multiple internal flushes');
    }

    @isTest
    static void testQuiddityIsCapturedAutomatically() {
        Test.startTest();
        Logger.error('LoggerTest.testQuiddityIsCapturedAutomatically', 'boom');
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Quiddity__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testQuiddityIsCapturedAutomatically'
        ];
        System.assertEquals(1, entries.size());
        System.assertNotEquals(null, entries[0].Quiddity__c, 'Quiddity should be populated automatically, not left blank');
    }
}
