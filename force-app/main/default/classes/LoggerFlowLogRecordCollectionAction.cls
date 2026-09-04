/**
 * Flow action "Add Log Entry for a Record Collection" — buffers one log
 * entry per record in the collection, all sharing the same message/source.
 * Does NOT save; see LoggerFlowLogMessageAction's comment.
 */
public without sharing class LoggerFlowLogRecordCollectionAction {

    public class Request {
        @InvocableVariable(required=true) public String level;
        @InvocableVariable(required=true) public String source;
        @InvocableVariable(required=true) public String message;
        @InvocableVariable(required=true) public List<SObject> records;
        @InvocableVariable public String tags;
    }

    @InvocableMethod(label='Add Log Entry for a Record Collection' description='Buffers one log entry per record in the collection. Does NOT save — add a "Save Log" action after this.')
    public static void execute(List<Request> requests) {
        for (Request req : requests) {
            if (req.records == null) {
                continue;
            }
            for (SObject record : req.records) {
                LogEntryBuilder builder = LoggerFlowSupport.logOne(req.level, req.source, req.message, null);
                builder.setRecord(record);
                LoggerFlowSupport.addTagsFromCsv(builder, req.tags);
            }
        }
    }
}
