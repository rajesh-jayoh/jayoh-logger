trigger LogTrigger on Log__c (before insert, before update, after insert, after update) {
    LoggerPluginDispatcher.run(
        Schema.Log__c.SObjectType,
        Trigger.operationType,
        Trigger.new,
        Trigger.old,
        Trigger.newMap,
        Trigger.oldMap
    );
}
