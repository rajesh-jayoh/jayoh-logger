@isTest
private class LogLevelTest {
    @isTest
    static void testOrdinalOrdering() {
        System.assertEquals(0, LogLevel.ordinalOf('FINEST'));
        System.assertEquals(1, LogLevel.ordinalOf('DEBUG'));
        System.assertEquals(2, LogLevel.ordinalOf('INFO'));
        System.assertEquals(3, LogLevel.ordinalOf('WARN'));
        System.assertEquals(4, LogLevel.ordinalOf('ERROR'));
    }

    @isTest
    static void testCaseInsensitivity() {
        System.assertEquals(LogLevel.ERROR_ORD, LogLevel.ordinalOf('error'));
        System.assertEquals(LogLevel.WARN_ORD, LogLevel.ordinalOf('Warn'));
    }

    @isTest
    static void testBlankAndUnknownDefaultToInfo() {
        System.assertEquals(LogLevel.INFO_ORD, LogLevel.ordinalOf(null));
        System.assertEquals(LogLevel.INFO_ORD, LogLevel.ordinalOf(''));
        System.assertEquals(LogLevel.INFO_ORD, LogLevel.ordinalOf('NOT_A_LEVEL'));
    }
}
