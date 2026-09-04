/**
 * Implement this to add your own automation to Log__c or Log_Entry__c
 * without modifying this package's own trigger code. Register the
 * implementing class in a Log_Plugin__mdt record (SObjectApiName__c set to
 * "Log__c" or "Log_Entry__c", ApexClassName__c set to your class's name).
 *
 * Example:
 *   public class MyLogPriorityPlugin implements LoggerPluginTriggerable {
 *       public void execute(LoggerPluginContext context) {
 *           if (context.triggerOperationType != System.TriggerOperation.BEFORE_INSERT) {
 *               return;
 *           }
 *           for (Log__c log : (List<Log__c>) context.triggerNew) {
 *               if (log.HighestSeverity__c == 'ERROR') {
 *                   log.Priority__c = 'Critical';
 *               }
 *           }
 *       }
 *   }
 *
 * Your class needs a no-argument constructor — it's instantiated via
 * Type.forName(className).newInstance().
 */
public interface LoggerPluginTriggerable {
    void execute(LoggerPluginContext context);
}
