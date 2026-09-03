@isTest
private class LogAlertServiceTest {

    @isTest
    static void testEmailSentWhenEnabledAndRecipientsConfigured() {
        LogAlertService.mockSettings = new Log_Alert_Setting__mdt(
            EmailEnabled__c = true,
            EmailRecipients__c = 'test@example.com',
            SlackEnabled__c = false
        );

        List<Log_Entry__c> errors = new List<Log_Entry__c>{
            new Log_Entry__c(Level__c = 'ERROR', Source__c = 'Test.source', Message__c = 'boom')
        };

        Integer before = Limits.getEmailInvocations();
        Test.startTest();
        LogAlertService.notifyOnErrors(errors);
        Test.stopTest();

        System.assert(Limits.getEmailInvocations() > before, 'Expected an email invocation when EmailEnabled__c is true');
    }

    @isTest
    static void testNoEmailWhenDisabled() {
        LogAlertService.mockSettings = new Log_Alert_Setting__mdt(
            EmailEnabled__c = false,
            SlackEnabled__c = false
        );

        List<Log_Entry__c> errors = new List<Log_Entry__c>{
            new Log_Entry__c(Level__c = 'ERROR', Source__c = 'Test.source', Message__c = 'boom')
        };

        Integer before = Limits.getEmailInvocations();
        Test.startTest();
        LogAlertService.notifyOnErrors(errors);
        Test.stopTest();

        System.assertEquals(before, Limits.getEmailInvocations(), 'No email should be sent when disabled');
    }

    @isTest
    static void testSlackEnqueuesJobWhenEnabled() {
        LogAlertService.mockSettings = new Log_Alert_Setting__mdt(
            EmailEnabled__c = false,
            SlackEnabled__c = true,
            SlackWebhookUrl__c = 'https://hooks.slack.com/services/test'
        );

        List<Log_Entry__c> errors = new List<Log_Entry__c>{
            new Log_Entry__c(Level__c = 'ERROR', Source__c = 'Test.source', Message__c = 'boom')
        };

        Test.startTest();
        LogAlertService.notifyOnErrors(errors);
        System.assertEquals(1, Limits.getQueueableJobs(), 'A queueable Slack job should be enqueued');
        Test.stopTest();
    }

    @isTest
    static void testEmptyEntriesIsNoOp() {
        Test.startTest();
        LogAlertService.notifyOnErrors(new List<Log_Entry__c>());
        Test.stopTest();
        System.assertEquals(0, Limits.getQueueableJobs());
    }
}
