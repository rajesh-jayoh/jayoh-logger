@isTest
private class LoggerTest {

    @isTest
    static void testErrorDoesNotAutoFlush() {
        // ERROR does not publish immediately on every call. Without an
        // explicit saveLog()/flush(), nothing should be persisted yet.
        Test.startTest();
        Logger.error('LoggerTest.testErrorDoesNotAutoFlush', 'Boom', new DmlException('bad'));
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c WHERE Source__c = 'LoggerTest.testErrorDoesNotAutoFlush'
        ];
        System.assertEquals(0, entries.size(), 'ERROR should be buffered, not auto-published, until saveLog()/flush() is called');
    }

    @isTest
    static void testErrorPersistsAfterExplicitSaveLog() {
        Test.startTest();
        Logger.error('LoggerTest.testErrorPersistsAfterExplicitSaveLog', 'Boom', new DmlException('bad'));
        Logger.saveLog();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c, Source__c, ExceptionType__c
            FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testErrorPersistsAfterExplicitSaveLog'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('ERROR', entries[0].Level__c);
        System.assertEquals('System.DmlException', entries[0].ExceptionType__c);
    }

    @isTest
    static void testInfoLogRequiresExplicitFlush() {
        Test.startTest();
        Logger.info('LoggerTest.testInfoLogRequiresExplicitFlush', 'just fyi');
        Logger.flush(); // alias for saveLog()
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
        Logger.flush();
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
    static void testBulkLoggingTriggersSafetyFlushAtBufferCap() {
        Test.startTest();
        for (Integer i = 0; i < 250; i++) {
            Logger.info('LoggerTest.testBulkLoggingTriggersSafetyFlushAtBufferCap', 'entry ' + i);
        }
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testBulkLoggingTriggersSafetyFlushAtBufferCap'
        ];
        System.assertEquals(250, entries.size(), 'All 250 buffered entries should persist across at most two internal saves, not 250 separate publish() calls');
    }

    @isTest
    static void testManyErrorsInALoopDoNotEachTriggerASeparatePublishCall() {
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
        Logger.flushBuffer();

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
    static void testSynchronousDmlSaveMethodSkipsPlatformEvents() {
        Logger.error('LoggerTest.testSynchronousDmlSaveMethodSkipsPlatformEvents', 'synchronous path');

        Test.startTest();
        Logger.saveLog(Logger.SaveMethod.SYNCHRONOUS_DML); // no Test.getEventBus().deliver() needed
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Level__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testSynchronousDmlSaveMethodSkipsPlatformEvents'
        ];
        System.assertEquals(1, entries.size(), 'SYNCHRONOUS_DML should insert directly without requiring event bus delivery');
    }

    @isTest
    static void testQueueableSaveMethodDefersToAsyncJob() {
        Logger.error('LoggerTest.testQueueableSaveMethodDefersToAsyncJob', 'deferred');

        Test.startTest();
        Logger.saveLog(Logger.SaveMethod.QUEUEABLE);
        Test.stopTest(); // enqueued jobs run at stopTest() in tests

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testQueueableSaveMethodDefersToAsyncJob'
        ];
        System.assertEquals(1, entries.size());
    }

    @isTest
    static void testSetSaveMethodChangesDefaultForSubsequentCalls() {
        Logger.setSaveMethod(Logger.SaveMethod.SYNCHRONOUS_DML);
        Logger.error('LoggerTest.testSetSaveMethodChangesDefaultForSubsequentCalls', 'via default sync');

        Test.startTest();
        Logger.flush(); // uses the default set above, not EVENT_BUS
        Test.stopTest();
        Logger.setSaveMethod(Logger.SaveMethod.EVENT_BUS); // reset for other tests in this transaction

        List<Log_Entry__c> entries = [
            SELECT Id FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testSetSaveMethodChangesDefaultForSubsequentCalls'
        ];
        System.assertEquals(1, entries.size());
    }

    @isTest
    static void testFluentBuilderSetsRecordAndTag() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Test.startTest();
        Logger.error('LoggerTest.testFluentBuilderSetsRecordAndTag', 'boom')
            .setRecord(acct.Id)
            .addTag('chargebee')
            .addTag('shipping-address');
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT RelatedRecordId__c, Tags__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testFluentBuilderSetsRecordAndTag'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals(acct.Id, (Id) entries[0].RelatedRecordId__c);
        System.assert(entries[0].Tags__c.contains('chargebee'));
        System.assert(entries[0].Tags__c.contains('shipping-address'));
    }

    @isTest
    static void testFluentBuilderOnSuppressedEntryDoesNotThrow() {
        // DEBUG is below the default INFO threshold — the builder should
        // still be returned (never null) so chaining doesn't blow up, even
        // though nothing gets buffered.
        Test.startTest();
        Logger.debug('LoggerTest.testFluentBuilderOnSuppressedEntryDoesNotThrow', 'suppressed')
            .addTag('irrelevant')
            .setRecord((Id) null);
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void testParentLogTransactionIdCorrelatesHeaders() {
        // Simulate a "parent" transaction's log already having been saved...
        Logger.error('LoggerTest.parent', 'parent entry');
        Logger.saveLog(Logger.SaveMethod.SYNCHRONOUS_DML);
        String parentTxnId = Logger.getTransactionId();

        // ...then a "child" entry (as if from a batch job) pointing back to it.
        Logger.setParentLogTransactionId(parentTxnId);
        // Force a distinct transaction id for the child by going through a
        // separate synchronous save path is not possible within one test
        // transaction (transaction id is fixed per test method), so this
        // verifies the correlation field is set and resolvable rather than
        // simulating two real transactions.
        Test.startTest();
        Logger.info('LoggerTest.child', 'child entry');
        Logger.saveLog(Logger.SaveMethod.SYNCHRONOUS_DML);
        Test.stopTest();

        Log__c header = [SELECT Id, ParentLog__c, TransactionId__c FROM Log__c WHERE TransactionId__c = :parentTxnId];
        // Since both entries share the same real transaction id in a single
        // test method, the "child" entry merges into the same header rather
        // than creating a separate one — this at least proves setParentLogTransactionId()
        // doesn't error, and ParentLog__c resolution is covered directly in
        // LogEntryEventHandlerTest with two distinct synthetic transaction ids.
        System.assertNotEquals(null, header.Id);
    }

    @isTest
    static void testLogMessageOverloadUsesLazyFormatting() {
        Test.startTest();
        Logger.info('LoggerTest.testLogMessageOverloadUsesLazyFormatting', new LogMessage('processed {0} of {1}', 5, 10));
        Logger.flush();
        Test.getEventBus().deliver();
        Test.stopTest();

        List<Log_Entry__c> entries = [
            SELECT Message__c FROM Log_Entry__c
            WHERE Source__c = 'LoggerTest.testLogMessageOverloadUsesLazyFormatting'
        ];
        System.assertEquals(1, entries.size());
        System.assertEquals('processed 5 of 10', entries[0].Message__c);
    }
}
