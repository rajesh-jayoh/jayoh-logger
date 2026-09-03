/**
 * Backs Logger.SaveMethod.QUEUEABLE — defers the actual insert of
 * Log__c/Log_Entry__c to a separate asynchronous transaction, which gets its
 * own independent governor limits. Useful when the current transaction is
 * already tight on CPU time or DML statements from other work, and the log
 * entries themselves don't need to survive an immediate rollback (they're
 * queued as a job, not published as a platform event, so this trades
 * rollback-safety for limit isolation — pick EVENT_BUS instead if you need
 * both).
 */
public class LogSaveQueueable implements Queueable {

    private final List<Log_Entry_Event__e> events;

    public LogSaveQueueable(List<Log_Entry_Event__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext ctx) {
        LogEntryEventHandler.handle(events);
    }
}
