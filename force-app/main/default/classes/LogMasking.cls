/**
 * Scrubs sensitive-looking values out of log messages before they're
 * persisted. Patterns are sourced from Log_Masking_Pattern__mdt so each
 * client org can add its own (e.g. a Chargebee API key prefix, an Intacct
 * account number format) without a code deploy. Falls back to a small
 * built-in denylist if no active Custom Metadata patterns exist.
 */
public class LogMasking {

    private static final List<Pattern> FALLBACK_PATTERNS = new List<Pattern>{
        Pattern.compile('\\b(?:\\d[ -]*?){13,16}\\b'),                          // card numbers
        Pattern.compile('\\b\\d{3}-\\d{2}-\\d{4}\\b'),                          // SSN
        Pattern.compile('(?i)(api[_-]?key|token|secret)\\s*[:=]\\s*\\S+')       // key/token=value pairs
    };

    @TestVisible
    private static List<String> mockPatternStrings = null;

    public static String mask(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        String result = value;
        for (Pattern p : getPatterns()) {
            Matcher m = p.matcher(result);
            result = m.replaceAll('***MASKED***');
        }
        return result;
    }

    private static List<Pattern> compiledCache = null;

    private static List<Pattern> getPatterns() {
        if (compiledCache != null) {
            return compiledCache;
        }

        List<String> patternStrings = mockPatternStrings;
        if (patternStrings == null) {
            patternStrings = new List<String>();
            for (Log_Masking_Pattern__mdt rec : [
                SELECT RegexPattern__c FROM Log_Masking_Pattern__mdt WHERE Active__c = true
            ]) {
                patternStrings.add(rec.RegexPattern__c);
            }
        }

        List<Pattern> compiled = new List<Pattern>();
        if (patternStrings.isEmpty()) {
            compiled.addAll(FALLBACK_PATTERNS);
        } else {
            for (String ps : patternStrings) {
                try {
                    compiled.add(Pattern.compile(ps));
                } catch (Exception ex) {
                    System.debug(LoggingLevel.WARN, 'LogMasking: skipping invalid pattern "' + ps + '": ' + ex.getMessage());
                }
            }
        }
        compiledCache = compiled;
        return compiled;
    }
}
