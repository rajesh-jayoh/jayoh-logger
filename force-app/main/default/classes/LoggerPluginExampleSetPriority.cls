/**
 * Example plugin, shipped disabled by default (see the matching
 * Log_Plugin__mdt record) — a working reference for how to write your own,
 * not something you're expected to actually use as-is. Auto-escalates
 * Log__c.Priority__c to "Critical" whenever HighestSeverity__c is ERROR and
 * Priority__c hasn't already been set to something more specific.
 *
 * Enable it by flipping Log_Plugin__mdt.Example_Set_Priority.IsEnabled__c
 * to true, or use it as a template for your own plugin.
 */
public class LoggerPluginExampleSetPriority implements LoggerPluginTriggerable {

    public void execute(LoggerPluginContext context) {
        if (context.sobjectType != Schema.Log__c.SObjectType) {
            return;
        }
        if (context.triggerOperationType != System.TriggerOperation.BEFORE_INSERT
            && context.triggerOperationType != System.TriggerOperation.BEFORE_UPDATE) {
            return;
        }

        for (Log__c log : (List<Log__c>) context.triggerNew) {
            if (log.HighestSeverity__c == 'ERROR' && log.Priority__c != 'Critical') {
                log.Priority__c = 'Critical';
            }
        }
    }
}
