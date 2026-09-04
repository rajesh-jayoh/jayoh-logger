/**
 * Flow action "Save Log" — publishes everything buffered so far by any of
 * JayOh Logger's Flow actions in this transaction. Call once, after any
 * loop, not inside it. Takes no inputs — Flow supports zero-parameter
 * invocable methods for actions like this that don't need configuration.
 */
public without sharing class LoggerFlowSaveLogAction {

    @InvocableMethod(label='Save Log' description='Publishes everything buffered so far by JayOh Logger\'s Flow actions in this transaction.')
    public static void execute() {
        Logger.saveLog();
    }
}
