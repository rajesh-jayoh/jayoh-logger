trigger LogEntryTrigger on Log_Entry__c (before insert, before update, after insert, after update) {
    LoggerPluginDispatcher.run(
        Schema.Log_Entry__c.SObjectType,
        Trigger.operationType,
        Trigger.new,
        Trigger.old,
        Trigger.newMap,
        Trigger.oldMap
    );
}
