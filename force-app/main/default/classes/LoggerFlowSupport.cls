/**
 * Shared helpers for the LoggerFlow*Action classes — kept separate from
 * those classes (rather than duplicated in each) since each one must stay a
 * single-@InvocableMethod class for Flow to reference it unambiguously by
 * class name.
 */
public without sharing class LoggerFlowSupport {

    public static LogEntryBuilder logOne(String level, String source, String message, Id relatedRecordId) {
        switch on (String.isBlank(level) ? 'INFO' : level.toUpperCase()) {
            when 'ERROR' { return Logger.error(source, message, null, relatedRecordId); }
            when 'WARN'  { return Logger.warn(source, message); }
            when 'DEBUG' { return Logger.debug(source, message); }
            when else    { return Logger.info(source, message); }
        }
    }

    public static void addTagsFromCsv(LogEntryBuilder builder, String tagsCsv) {
        if (String.isBlank(tagsCsv)) {
            return;
        }
        for (String tag : tagsCsv.split(',')) {
            builder.addTag(tag.trim());
        }
    }
}
