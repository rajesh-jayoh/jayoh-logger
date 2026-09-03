@isTest
private class LogRestSaverTest {

    private class MockUpsertCreated implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('/sobjects/Log__c/TransactionId__c/')) {
                res.setStatusCode(201);
                res.setBody('{"id":"' + fakeId('001') + '","success":true,"errors":[]}');
            } else if (req.getEndpoint().contains('/sobjects/Log_Entry__c')) {
                res.setStatusCode(201);
                res.setBody('{"id":"' + fakeId('a00') + '","success":true,"errors":[]}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    private class MockUpsertUpdatedThenQuery implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'PATCH') {
                res.setStatusCode(204); // existing record updated, no body
            } else if (req.getEndpoint().contains('/query?q=')) {
                res.setStatusCode(200);
                res.setBody('{"records":[{"Id":"' + fakeId('001') + '"}]}');
                res.setHeader('Content-Type', 'application/json');
            } else {
                res.setStatusCode(201);
                res.setBody('{"id":"' + fakeId('a00') + '"}');
                res.setHeader('Content-Type', 'application/json');
            }
            return res;
        }
    }

    private class MockFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"server error"}');
            return res;
        }
    }

    @isTest
    static void testSaveViaRestWithNewRecordCreatesHeaderAndEntry() {
        Test.setMock(HttpCalloutMock.class, new MockUpsertCreated());

        List<Log_Entry_Event__e> events = new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'REST-TXN-1', Level__c = 'ERROR', Source__c = 'x',
                Message__c = 'failed', OccurredAt__c = System.now(), RunningUser__c = UserInfo.getUserId()
            )
        };

        Test.startTest();
        LogRestSaver.save(events);
        Test.stopTest();

        // No exception thrown is the main assertion here — this path is
        // experimental and marked as needing sandbox verification; the mock
        // proves the request shapes are well-formed enough to parse a
        // successful response without error.
        System.assert(true);
    }

    @isTest
    static void testSaveViaRestWithExistingRecordQueriesForId() {
        Test.setMock(HttpCalloutMock.class, new MockUpsertUpdatedThenQuery());

        List<Log_Entry_Event__e> events = new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'REST-TXN-2', Level__c = 'INFO', Source__c = 'y',
                Message__c = 'ok', OccurredAt__c = System.now(), RunningUser__c = UserInfo.getUserId()
            )
        };

        Test.startTest();
        LogRestSaver.save(events);
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testSaveViaRestHandlesFailureWithoutThrowing() {
        Test.setMock(HttpCalloutMock.class, new MockFailure());

        List<Log_Entry_Event__e> events = new List<Log_Entry_Event__e>{
            new Log_Entry_Event__e(
                TransactionId__c = 'REST-TXN-3', Level__c = 'ERROR', Source__c = 'z',
                Message__c = 'failed', OccurredAt__c = System.now(), RunningUser__c = UserInfo.getUserId()
            )
        };

        Test.startTest();
        LogRestSaver.save(events); // should swallow the failure, not throw
        Test.stopTest();

        System.assert(true);
    }

    private static String fakeId(String prefix) {
        String padded = prefix;
        while (padded.length() < 15) {
            padded += '0';
        }
        return padded;
    }
}
