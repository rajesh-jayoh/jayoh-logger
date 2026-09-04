/**
 * Flow action "Add Log Entry for a Record" — buffers a log entry linked to a
 * specific record. Does NOT save; see LoggerFlowLogMessageAction's comment.
 */
public without sharing class LoggerFlowLogRecordAction {

    public class Request {
        @InvocableVariable(required=true) public String level;
        @InvocableVariable(required=true) public String source;
        @InvocableVariable(required=true) public String message;
        @InvocableVariable(required=true) public SObject record;
        @InvocableVariable public String tags;
    }

    @InvocableMethod(label='Add Log Entry for a Record' description='Buffers a log entry linked to a specific record. Does NOT save — add a "Save Log" action after this.')
    public static void execute(List<Request> requests) {
        for (Request req : requests) {
            LogEntryBuilder builder = LoggerFlowSupport.logOne(req.level, req.source, req.message, null);
            builder.setRecord(req.record);
            LoggerFlowSupport.addTagsFromCsv(builder, req.tags);
        }
    }
}
