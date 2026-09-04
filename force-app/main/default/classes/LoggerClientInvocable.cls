/**
 * AuraEnabled entry point for LWC/Aura client-side logging. Not a Flow
 * action, so it doesn't need the single-@InvocableMethod-per-class split
 * that the LoggerFlow*Action classes require.
 */
public without sharing class LoggerClientInvocable {

    @AuraEnabled
    public static void logFromClient(String level, String source, String message, Id relatedRecordId) {
        LoggerFlowSupport.logOne(level, source, message, relatedRecordId);
        Logger.flush(); // single call per client-side invocation — each imperative Apex call from LWC/Aura is already its own transaction
    }
}
