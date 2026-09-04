/**
 * Looks up enabled Log_Plugin__mdt records for the given object and runs each
 * one's Apex class. Called from LogTrigger and LogEntryTrigger — not meant to
 * be called directly.
 *
 * Safety guarantees:
 * - One plugin throwing an exception does NOT stop the others, or the
 *   underlying DML — it's caught and logged to System.debug (not through
 *   Logger itself, to avoid a plugin error on Log__c recursively triggering
 *   more Log__c inserts).
 * - Re-entrancy guard: if a plugin's own logic causes another Log__c/Log_Entry__c
 *   DML (directly, not through Logger — Logger's own inserts happen once per
 *   platform event delivery, not from inside this dispatcher), the dispatcher
 *   will still run for that nested trigger invocation. Plugin authors are
 *   responsible for not writing infinite recursion into their own plugin.
 */
public without sharing class LoggerPluginDispatcher {

    @TestVisible
    private static List<Log_Plugin__mdt> mockPlugins = null;

    public static void run(
        Schema.SObjectType sobjectType,
        System.TriggerOperation triggerOperationType,
        List<SObject> triggerNew,
        List<SObject> triggerOld,
        Map<Id, SObject> triggerNewMap,
        Map<Id, SObject> triggerOldMap
    ) {
        String sobjectApiName = sobjectType.getDescribe().getName();
        List<Log_Plugin__mdt> plugins = getPluginsForObject(sobjectApiName);
        if (plugins.isEmpty()) {
            return;
        }

        LoggerPluginContext context = new LoggerPluginContext(
            sobjectType, triggerOperationType, triggerNew, triggerOld, triggerNewMap, triggerOldMap
        );

        for (Log_Plugin__mdt pluginConfig : plugins) {
            runOnePlugin(pluginConfig, context);
        }
    }

    private static void runOnePlugin(Log_Plugin__mdt pluginConfig, LoggerPluginContext context) {
        try {
            Type pluginType = Type.forName(pluginConfig.ApexClassName__c);
            if (pluginType == null) {
                System.debug(LoggingLevel.WARN, 'LoggerPluginDispatcher: class not found: ' + pluginConfig.ApexClassName__c);
                return;
            }
            Object instance = pluginType.newInstance();
            if (!(instance instanceof LoggerPluginTriggerable)) {
                System.debug(LoggingLevel.WARN, 'LoggerPluginDispatcher: ' + pluginConfig.ApexClassName__c + ' does not implement LoggerPluginTriggerable');
                return;
            }
            ((LoggerPluginTriggerable) instance).execute(context);
        } catch (Exception ex) {
            // Deliberately System.debug, not Logger.error() — a plugin failing
            // on the Log__c/Log_Entry__c trigger must not recursively cause
            // more Log__c/Log_Entry__c DML from inside that same trigger.
            System.debug(LoggingLevel.ERROR, 'LoggerPluginDispatcher: plugin ' + pluginConfig.ApexClassName__c + ' threw: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
        }
    }

    private static List<Log_Plugin__mdt> getPluginsForObject(String sobjectApiName) {
        List<Log_Plugin__mdt> source = mockPlugins != null
            ? mockPlugins
            : [
                SELECT ApexClassName__c, SObjectApiName__c, ExecutionOrder__c, IsEnabled__c
                FROM Log_Plugin__mdt
                WHERE IsEnabled__c = true
                ORDER BY ExecutionOrder__c ASC
              ];

        List<Log_Plugin__mdt> matching = new List<Log_Plugin__mdt>();
        for (Log_Plugin__mdt p : source) {
            if (p.SObjectApiName__c == sobjectApiName && p.IsEnabled__c == true) {
                matching.add(p);
            }
        }
        return matching;
    }
}
