/**
 * Entry points for non-Apex callers: Flow (invocable) and LWC/Aura (AuraEnabled).
 * Both funnel into the same Logger so behavior (masking, level filtering,
 * platform-event persistence) is identical regardless of origin.
 */
public without sharing class LoggerInvocable {

    public class LogRequest {
        @InvocableVariable(required=true) public String level;    // ERROR, WARN, INFO, DEBUG
        @InvocableVariable(required=true) public String source;   // e.g. Flow name or component name
        @InvocableVariable(required=true) public String message;
        @InvocableVariable public Id relatedRecordId;
    }

    @InvocableMethod(label='Log Message' description='Writes an entry via the JayOh Logger from Flow.')
    public static void logFromFlow(List<LogRequest> requests) {
        for (LogRequest req : requests) {
            logOne(req.level, req.source, req.message, req.relatedRecordId);
        }
        Logger.flush();
    }

    @AuraEnabled
    public static void logFromClient(String level, String source, String message, Id relatedRecordId) {
        logOne(level, source, message, relatedRecordId);
        Logger.flush();
    }

    private static void logOne(String level, String source, String message, Id relatedRecordId) {
        switch on (String.isBlank(level) ? 'INFO' : level.toUpperCase()) {
            when 'ERROR' { Logger.error(source, message, null, relatedRecordId); }
            when 'WARN'  { Logger.warn(source, message); }
            when 'DEBUG' { Logger.debug(source, message); }
            when else    { Logger.info(source, message); }
        }
    }
}
