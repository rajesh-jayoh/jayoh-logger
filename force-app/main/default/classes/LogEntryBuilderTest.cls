@isTest
private class LogEntryBuilderTest {

    @isTest
    static void testSetRecordWithSObjectSetsRelatedRecordId() {
        Account acct = new Account(Name = 'Builder Test Account');
        insert acct;

        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        new LogEntryBuilder(evt).setRecord(acct);

        System.assertEquals(acct.Id, (Id) evt.RelatedRecordId__c);
    }

    @isTest
    static void testSetRecordWithNullSObjectDoesNotThrow() {
        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        new LogEntryBuilder(evt).setRecord((SObject) null);
        System.assertEquals(null, evt.RelatedRecordId__c);
    }

    @isTest
    static void testSetExceptionDetailsPopulatesFields() {
        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        try {
            Integer x = 1 / 0;
        } catch (Exception ex) {
            new LogEntryBuilder(evt).setExceptionDetails(ex);
            System.assertEquals(ex.getTypeName(), evt.ExceptionType__c);
            System.assertNotEquals(null, evt.StackTrace__c);
        }
    }

    @isTest
    static void testSetExceptionDetailsWithNullDoesNotThrow() {
        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        new LogEntryBuilder(evt).setExceptionDetails(null);
        System.assertEquals(null, evt.ExceptionType__c);
    }

    @isTest
    static void testAddTagsWithListAppendsAllSemicolonSeparated() {
        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        new LogEntryBuilder(evt).addTags(new List<String>{ 'one', 'two', 'three' });
        System.assertEquals('one;two;three', evt.Tags__c);
    }

    @isTest
    static void testAddTagSkipsBlankValues() {
        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        new LogEntryBuilder(evt).addTag('real').addTag('').addTag(null).addTag('also-real');
        System.assertEquals('real;also-real', evt.Tags__c);
    }

    @isTest
    static void testChainingReturnsSameBuilderInstance() {
        Log_Entry_Event__e evt = new Log_Entry_Event__e();
        LogEntryBuilder builder = new LogEntryBuilder(evt);
        LogEntryBuilder chained = builder.setRecord((Id) null).addTag('x').setExceptionDetails(null);
        System.assertEquals('x', evt.Tags__c);
    }
}
