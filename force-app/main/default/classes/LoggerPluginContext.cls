/**
 * Everything a plugin needs about the trigger invocation that's running it.
 * Deliberately mirrors the shape of Trigger.* context variables rather than
 * inventing new names, since anyone writing Apex triggers already knows this shape.
 */
public class LoggerPluginContext {
    public Schema.SObjectType sobjectType;
    public System.TriggerOperation triggerOperationType;
    public List<SObject> triggerNew;
    public List<SObject> triggerOld;
    public Map<Id, SObject> triggerNewMap;
    public Map<Id, SObject> triggerOldMap;

    public LoggerPluginContext(
        Schema.SObjectType sobjectType,
        System.TriggerOperation triggerOperationType,
        List<SObject> triggerNew,
        List<SObject> triggerOld,
        Map<Id, SObject> triggerNewMap,
        Map<Id, SObject> triggerOldMap
    ) {
        this.sobjectType = sobjectType;
        this.triggerOperationType = triggerOperationType;
        this.triggerNew = triggerNew;
        this.triggerOld = triggerOld;
        this.triggerNewMap = triggerNewMap;
        this.triggerOldMap = triggerOldMap;
    }
}
