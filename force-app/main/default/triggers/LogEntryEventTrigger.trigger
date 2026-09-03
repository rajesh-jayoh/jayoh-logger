trigger LogEntryEventTrigger on Log_Entry_Event__e (after insert) {
    // Platform event triggers commit independently of the transaction that
    // published the event — this is what makes an ERROR-level log survive
    // even when the original transaction rolls back.
    LogEntryEventHandler.handle(Trigger.new);
}
