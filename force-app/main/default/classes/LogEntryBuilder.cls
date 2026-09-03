/**
 * Fluent builder returned by every Logger.error()/warn()/info()/debug() call.
 * Wraps the same Log_Entry_Event__e instance Logger already buffered, so
 * chained calls mutate that entry in place — nothing extra is buffered or
 * published until Logger.flush()/saveLog() actually runs.
 *
 *   Logger.error('CBHttpClient.patch', 'Callout failed', ex)
 *       .setRecord(quote.Id)
 *       .addTag('chargebee')
 *       .addTag('shipping-address');
 */
public class LogEntryBuilder {

    private final Log_Entry_Event__e event;

    public LogEntryBuilder(Log_Entry_Event__e event) {
        this.event = event;
    }

    public LogEntryBuilder setRecord(Id recordId) {
        event.RelatedRecordId__c = recordId;
        return this;
    }

    public LogEntryBuilder setRecord(SObject record) {
        if (record != null) {
            event.RelatedRecordId__c = record.Id;
        }
        return this;
    }

    public LogEntryBuilder setExceptionDetails(Exception ex) {
        if (ex != null) {
            event.ExceptionType__c    = ex.getTypeName();
            event.ExceptionMessage__c = LogMasking.mask(ex.getMessage());
            event.StackTrace__c       = ex.getStackTraceString();
        }
        return this;
    }

    public LogEntryBuilder addTag(String tagName) {
        if (String.isBlank(tagName)) {
            return this;
        }
        String existing = event.Tags__c;
        event.Tags__c = String.isBlank(existing) ? tagName : existing + ';' + tagName;
        return this;
    }

    public LogEntryBuilder addTags(List<String> tagNames) {
        if (tagNames == null) {
            return this;
        }
        for (String tagName : tagNames) {
            addTag(tagName);
        }
        return this;
    }
}
