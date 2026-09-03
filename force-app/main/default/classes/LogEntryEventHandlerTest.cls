@isTest
private class LogEntryEventHandlerTest {

    @isTest
    static void testHandleCreatesHeaderAndEntry() {
        Log_Entry_Event__e evt = new Log_Entry_Event__e(
            TransactionId__c = '1234-TEST',
            Level__c = 'ERROR',
            Source__c = 'LogEntryEventHandlerTest.testHandleCreatesHeaderAndEntry',
            Message__c = 'Something went wrong',
            OccurredAt__c = System.now(),
            RunningUser__c = UserInfo.getUserId()
        );

        Test.startTest();
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{ evt });
        Test.stopTest();

        List<Log__c> headers = [SELECT Id, TransactionId__c, HighestSeverity__c FROM Log__c WHERE TransactionId__c = '1234-TEST'];
        System.assertEquals(1, headers.size());
        System.assertEquals('ERROR', headers[0].HighestSeverity__c);

        List<Log_Entry__c> entries = [SELECT Id, Message__c, Level__c FROM Log_Entry__c WHERE Log__c = :headers[0].Id];
        System.assertEquals(1, entries.size());
        System.assertEquals('Something went wrong', entries[0].Message__c);
    }

    @isTest
    static void testHandleMergesWithExistingHeaderForSameTransaction() {
        // First flush: an INFO entry
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'TXN-MERGE',
                Level__c = 'INFO',
                Source__c = 'first',
                Message__c = 'starting',
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            )
        });

        // Second flush, same transaction id, higher severity
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'TXN-MERGE',
                Level__c = 'ERROR',
                Source__c = 'second',
                Message__c = 'failed',
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            )
        });

        List<Log__c> headers = [SELECT Id, HighestSeverity__c FROM Log__c WHERE TransactionId__c = 'TXN-MERGE'];
        System.assertEquals(1, headers.size(), 'Should not create a duplicate header for the same transaction id');
        System.assertEquals('ERROR', headers[0].HighestSeverity__c, 'Header should reflect the highest severity seen');

        List<Log_Entry__c> entries = [SELECT Id FROM Log_Entry__c WHERE Log__c = :headers[0].Id];
        System.assertEquals(2, entries.size());
    }

    @isTest
    static void testHandleIgnoresEmptyList() {
        // Should not throw
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>());
        System.assert(true);
    }

    @isTest
    static void testParentLogTransactionIdResolvesToParentLookupWhenParentAlreadyPersisted() {
        // Persist the "parent" transaction's header first.
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'PARENT-TXN',
                Level__c = 'INFO',
                Source__c = 'parent',
                Message__c = 'parent started',
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            )
        });

        // Now a "child" transaction (as if from a batch job's execute()) that
        // points back to it via ParentLogTransactionId__c.
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'CHILD-TXN',
                ParentLogTransactionId__c = 'PARENT-TXN',
                Level__c = 'INFO',
                Source__c = 'child',
                Message__c = 'processed a batch scope',
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            )
        });

        Log__c parentLog = [SELECT Id FROM Log__c WHERE TransactionId__c = 'PARENT-TXN'];
        Log__c childLog = [SELECT Id, ParentLog__c FROM Log__c WHERE TransactionId__c = 'CHILD-TXN'];

        System.assertEquals(parentLog.Id, childLog.ParentLog__c, 'Child header should be linked to the already-persisted parent header');
    }

    @isTest
    static void testParentLogTransactionIdLeavesBlankWhenParentNotYetPersisted() {
        // No 'PARENT-NOT-YET' header exists — resolution should silently
        // leave ParentLog__c blank rather than failing the whole save.
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'ORPHAN-CHILD-TXN',
                ParentLogTransactionId__c = 'PARENT-NOT-YET',
                Level__c = 'INFO',
                Source__c = 'child',
                Message__c = 'processed before parent saved',
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            )
        });

        Log__c childLog = [SELECT ParentLog__c FROM Log__c WHERE TransactionId__c = 'ORPHAN-CHILD-TXN'];
        System.assertEquals(null, childLog.ParentLog__c);
    }

    @isTest
    static void testTagsAreNormalizedIntoLogTagAndJunctionRecords() {
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'TAG-TXN',
                Level__c = 'ERROR',
                Source__c = 'CBHttpClient.patch',
                Message__c = 'failed',
                Tags__c = 'chargebee;shipping-address',
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            )
        });

        List<Log_Tag__c> tags = [SELECT Name FROM Log_Tag__c WHERE Name IN ('chargebee', 'shipping-address')];
        System.assertEquals(2, tags.size());

        Log_Entry__c entry = [SELECT Id FROM Log_Entry__c WHERE Source__c = 'CBHttpClient.patch'];
        List<Log_Entry_Tag__c> junctions = [SELECT Log_Tag__r.Name FROM Log_Entry_Tag__c WHERE Log_Entry__c = :entry.Id];
        System.assertEquals(2, junctions.size());
    }

    @isTest
    static void testDuplicateTagNameAcrossEntriesReusesSameLogTagRecord() {
        LogEntryEventHandler.handle(new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'TAG-REUSE-TXN', Level__c = 'ERROR', Source__c = 'a',
                Message__c = 'first', Tags__c = 'chargebee', OccurredAt__c = System.now(), RunningUser__c = UserInfo.getUserId()
            ),
            new Log_Entry_Event__e(
                TransactionId__c = 'TAG-REUSE-TXN', Level__c = 'ERROR', Source__c = 'b',
                Message__c = 'second', Tags__c = 'chargebee', OccurredAt__c = System.now(), RunningUser__c = UserInfo.getUserId()
            )
        });

        List<Log_Tag__c> tags = [SELECT Id FROM Log_Tag__c WHERE Name = 'chargebee'];
        System.assertEquals(1, tags.size(), 'The same tag name used across multiple entries should reuse one Log_Tag__c record');

        List<Log_Entry_Tag__c> junctions = [SELECT Id FROM Log_Entry_Tag__c WHERE Log_Tag__c = :tags[0].Id];
        System.assertEquals(2, junctions.size(), 'Both entries should have their own junction row pointing at the shared tag');
    }

    @isTest
    static void testBulkHandlesTwoHundredEventsAcrossManyTransactions() {
        List<Log_Entry_Event__e> events = new List<Log_Entry_Event__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(new Log_Entry_Event__e(
                TransactionId__c = 'BULK-TXN-' + (Math.mod(i, 20)), // 20 distinct transactions, 10 entries each
                Level__c = Math.mod(i, 7) == 0 ? 'ERROR' : 'INFO',
                Source__c = 'LogEntryEventHandlerTest.bulk',
                Message__c = 'bulk entry ' + i,
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            ));
        }

        Test.startTest();
        LogEntryEventHandler.handle(events);
        Test.stopTest();

        List<Log__c> headers = [SELECT Id, HighestSeverity__c FROM Log__c WHERE TransactionId__c LIKE 'BULK-TXN-%'];
        System.assertEquals(20, headers.size(), 'Should collapse 200 entries into 20 headers, one per distinct transaction id');

        List<Log_Entry__c> entries = [SELECT Id FROM Log_Entry__c WHERE Log__r.TransactionId__c LIKE 'BULK-TXN-%'];
        System.assertEquals(200, entries.size(), 'Every entry should persist even at 200 in a single batch');

        for (Log__c header : headers) {
            System.assertEquals('ERROR', header.HighestSeverity__c, 'Every transaction group includes at least one ERROR-level entry');
        }
    }

    @isTest
    static void testBulkHandlesTwoHundredEventsForSameSingleTransaction() {
        List<Log_Entry_Event__e> events = new List<Log_Entry_Event__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(new Log_Entry_Event__e(
                TransactionId__c = 'SINGLE-BULK-TXN',
                Level__c = 'INFO',
                Source__c = 'LogEntryEventHandlerTest.bulkSingle',
                Message__c = 'entry ' + i,
                OccurredAt__c = System.now(),
                RunningUser__c = UserInfo.getUserId()
            ));
        }

        Test.startTest();
        LogEntryEventHandler.handle(events);
        Test.stopTest();

        List<Log__c> headers = [SELECT Id FROM Log__c WHERE TransactionId__c = 'SINGLE-BULK-TXN'];
        System.assertEquals(1, headers.size(), 'All 200 events for one transaction id should collapse to a single header');

        List<Log_Entry__c> entries = [SELECT Id FROM Log_Entry__c WHERE Log__c = :headers[0].Id];
        System.assertEquals(200, entries.size());
    }
}
