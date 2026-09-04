/**
 * Flow action "Log Message" — buffers a log entry. Does NOT save; add a
 * single "Save Log" action (LoggerFlowSaveLogAction) after this, once per
 * loop rather than inside it, or you risk the same per-transaction
 * EventBus.publish() limit documented in Logger.cls.
 */
public without sharing class LoggerFlowLogMessageAction {

    public class Request {
        @InvocableVariable(required=true) public String level;    // ERROR, WARN, INFO, DEBUG
        @InvocableVariable(required=true) public String source;   // e.g. Flow name
        @InvocableVariable(required=true) public String message;
        @InvocableVariable public Id relatedRecordId;
        @InvocableVariable public String tags;                    // comma-separated, e.g. "chargebee,renewal"
    }

    @InvocableMethod(label='Log Message' description='Buffers a log entry via JayOh Logger. Does NOT save — add a "Save Log" action after this (once per loop, not inside it).')
    public static void execute(List<Request> requests) {
        for (Request req : requests) {
            LogEntryBuilder builder = LoggerFlowSupport.logOne(req.level, req.source, req.message, req.relatedRecordId);
            LoggerFlowSupport.addTagsFromCsv(builder, req.tags);
        }
    }
}
