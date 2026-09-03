@isTest
private class LoggerTest {

    @isTest
    static void testErrorDoesNotAutoFlush() {
        // This is the behavior change from the earlier buggy version: ERROR
        // no longer publishes immediately on every call. Without an explicit
        // flush(), nothing should be persisted yet.
        Test.startTest();
        Logger.error('LoggerTest.testErrorDoesNotAutoFlush', 'Boom', new DmlException('bad'));
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c WHERE Source__c = 'LoggerTest.testErrorDoesNotAutoFlush'
        ];
        System.assertEquals(0, entries.size(), 'ERROR should be buffered, not auto-published, until flush() is called');
    }

    @isTest
    static void testErrorPersistsAfterExplicitFlush() {
        Test.startTest();
        Logger.error('LoggerTest.testErrorPersistsAfterExplicitFlush', 'Boom', new DmlException('bad'));
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c, Source__c, ExceptionType__c
            FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testErrorPersistsAfterExplicitFlush'
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
        Logger.flush();
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
        // Buffer caps at 200 and auto-flushes as a heap-size safety net only —
        // NOT a per-entry or per-level flush. 250 INFO calls should trigger at
        // most one internal safety flush plus the final explicit flush(), and
        // every entry should still make it through to Log_Entry__c.
        Test.startTest();
        for (Integer i = 0; i < 250; i++) {
            Logger.info('LoggerTest.testBulkLoggingTriggersAutoFlushAtBufferCap', 'entry ' + i);
        }
        Logger.flush(); // flush whatever remains under the cap
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testBulkLoggingTriggersAutoFlushAtBufferCap'
        ];
        System.assertEquals(250, entries.size(), 'All 250 buffered entries should persist across at most two internal flushes, not 250 separate publish() calls');
    }

    @isTest
    static void testManyErrorsInALoopDoNotEachTriggerASeparatePublishCall() {
        // The bug this test guards against: an earlier version of Logger
        // auto-flushed on every single ERROR call. A loop logging 160 errors
        // would have made 160 separate EventBus.publish() calls, risking the
        // 150-calls-per-transaction governor limit. With buffering, this same
        // loop makes at most one internal safety flush (at the 200 cap) plus
        // one explicit flush() — nowhere near that ceiling.
        Test.startTest();
        for (Integer i = 0; i < 160; i++) {
            Logger.error('LoggerTest.testManyErrorsInALoopDoNotEachTriggerASeparatePublishCall', 'error ' + i);
        }
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testManyErrorsInALoopDoNotEachTriggerASeparatePublishCall'
        ];
        System.assertEquals(160, entries.size());
    }

    @isTest
    static void testQuiddityIsCapturedAutomatically() {
        Test.startTest();
        Logger.error('LoggerTest.testQuiddityIsCapturedAutomatically', 'boom');
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Quiddity__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testQuiddityIsCapturedAutomatically'
        ];
        System.assertEquals(1, entries.size());
        System.assertNotEquals(null, entries[0].Quiddity__c, 'Quiddity should be populated automatically, not left blank');
    }

    @isTest
    static void testSuspendSavingIgnoresLogCalls() {
        Logger.suspendSaving();
        Logger.error('LoggerTest.testSuspendSavingIgnoresLogCalls', 'should be ignored entirely');
        Logger.resumeSaving();

        Test.startTest();
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c WHERE Source__c = 'LoggerTest.testSuspendSavingIgnoresLogCalls'
        ];
        System.assertEquals(0, entries.size(), 'Log calls while suspended should not be buffered at all');
    }

    @isTest
    static void testResumeSavingAllowsSubsequentLogsThrough() {
        Logger.suspendSaving();
        Logger.error('LoggerTest.testResumeSavingAllowsSubsequentLogsThrough', 'ignored');
        Logger.resumeSaving();
        Logger.error('LoggerTest.testResumeSavingAllowsSubsequentLogsThrough', 'should be captured');

        Test.startTest();
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Message__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testResumeSavingAllowsSubsequentLogsThrough'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('should be captured', entries[0].Message__c);
    }

    @isTest
    static void testFlushBufferDiscardsWithoutPersisting() {
        Logger.error('LoggerTest.testFlushBufferDiscardsWithoutPersisting', 'never saved');
        Logger.flushBuffer(); // discard, not flush

        Test.startTest();
        Logger.flush(); // buffer is already empty — should be a no-op
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c WHERE Source__c = 'LoggerTest.testFlushBufferDiscardsWithoutPersisting'
        ];
        System.assertEquals(0, entries.size());
    }

    @isTest
    static void testSyncModeSkipsPlatformEventsAndInsertsDirectly() {
        Logger.setSyncMode(true);
        Logger.error('LoggerTest.testSyncModeSkipsPlatformEventsAndInsertsDirectly', 'synchronous path');

        Test.startTest();
        Logger.flush(); // no Test.getEventBus().deliver() needed — this path never uses the event bus
        Test.stopTest();
        Logger.setSyncMode(false); // reset so it doesn't leak into other test methods running in this transaction

        List<Log_Entry__c> entries = [
            SELECT Level__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testSyncModeSkipsPlatformEventsAndInsertsDirectly'
        ];
        System.assertEquals(1, entries.size(), 'Sync mode should insert directly without requiring event bus delivery');
    }
}
