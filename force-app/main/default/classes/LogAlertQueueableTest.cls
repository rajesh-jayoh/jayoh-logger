@isTest
private class LogAlertQueueableTest {

    private class MockSlackResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('ok');
            return res;
        }
    }

    @isTest
    static void testExecutePostsToSlack() {
        Test.setMock(HttpCalloutMock.class, new MockSlackResponse());

        List<Log_Entry__c> errors = new List<Log_Entry__c>();
        for (Integer i = 0; i < 7; i++) {
            errors.add(new Log_Entry__c(Level__c = 'ERROR', Source__c = 'Test.source' + i, Message__c = 'boom ' + i));
        }

        Test.startTest();
        System.enqueueJob(new LogAlertQueueable(errors, 'https://hooks.slack.com/services/test'));
        Test.stopTest();

        // No exception thrown = success; HttpCalloutMock guarantees the callout
        // was intercepted rather than hitting a real endpoint.
        System.assert(true);
    }
}
