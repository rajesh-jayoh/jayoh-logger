@isTest
private class LogMessageTest {

    @isTest
    static void testNoInputsReturnsMessageUnchanged() {
        LogMessage msg = new LogMessage('plain message, no formatting');
        System.assertEquals('plain message, no formatting', msg.getMessage());
    }

    @isTest
    static void testSingleInputFormatsCorrectly() {
        LogMessage msg = new LogMessage('processed {0} records', 42);
        System.assertEquals('processed 42 records', msg.getMessage());
    }

    @isTest
    static void testTwoInputsFormatCorrectly() {
        LogMessage msg = new LogMessage('{0} of {1} succeeded', 8, 10);
        System.assertEquals('8 of 10 succeeded', msg.getMessage());
    }

    @isTest
    static void testThreeInputsFormatCorrectly() {
        LogMessage msg = new LogMessage('{0}-{1}-{2}', 'a', 'b', 'c');
        System.assertEquals('a-b-c', msg.getMessage());
    }

    @isTest
    static void testListOverloadFormatsCorrectly() {
        LogMessage msg = new LogMessage('{0} then {1} then {2} then {3}', new List<Object>{ 1, 2, 3, 4 });
        System.assertEquals('1 then 2 then 3 then 4', msg.getMessage());
    }

    @isTest
    static void testNullInputsListTreatedAsNoInputs() {
        LogMessage msg = new LogMessage('unchanged', (List<Object>) null);
        System.assertEquals('unchanged', msg.getMessage());
    }
}
