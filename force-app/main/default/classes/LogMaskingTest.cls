@isTest
private class LogMaskingTest {
    @isTest
    static void testMasksCardNumber() {
        String input = 'Payment failed for card 4111111111111111 on file';
        String result = LogMasking.mask(input);
        System.assert(!result.contains('4111111111111111'), 'Card number should be masked');
        System.assert(result.contains('***MASKED***'));
    }

    @isTest
    static void testMasksSsn() {
        String input = 'SSN on record: 123-45-6789';
        String result = LogMasking.mask(input);
        System.assert(!result.contains('123-45-6789'));
        System.assert(result.contains('***MASKED***'));
    }

    @isTest
    static void testMasksApiKeyPattern() {
        String input = 'Request failed, api_key=sk_live_abc123XYZ';
        String result = LogMasking.mask(input);
        System.assert(!result.contains('sk_live_abc123XYZ'));
    }

    @isTest
    static void testBlankInputReturnsUnchanged() {
        System.assertEquals(null, LogMasking.mask(null));
        System.assertEquals('', LogMasking.mask(''));
    }

    @isTest
    static void testNonSensitiveTextUnaffected() {
        String input = 'Processed 42 records successfully';
        System.assertEquals(input, LogMasking.mask(input));
    }

    @isTest
    static void testUsesInjectedMockPatternsInsteadOfFallback() {
        LogMasking.mockPatternStrings = new List<String>{ 'FOO\\d+' };
        String result = LogMasking.mask('order FOO123 failed, card 4111111111111111 fine');
        System.assert(!result.contains('FOO123'), 'Custom pattern should be applied');
        System.assert(result.contains('4111111111111111'), 'Fallback card pattern should NOT apply when mock patterns are injected');
    }

    @isTest
    static void testEmptyMockPatternListFallsBackToBuiltins() {
        LogMasking.mockPatternStrings = new List<String>();
        String result = LogMasking.mask('card 4111111111111111 declined');
        System.assert(!result.contains('4111111111111111'), 'Empty CMDT pattern list should fall back to built-in patterns');
    }

    @isTest
    static void testInvalidPatternIsSkippedWithoutThrowing() {
        LogMasking.mockPatternStrings = new List<String>{ '(unclosed' };
        String input = 'just a normal message';
        String result = LogMasking.mask(input);
        System.assertEquals(input, result, 'An invalid regex should be skipped rather than throwing');
    }
}
