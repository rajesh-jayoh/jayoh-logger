# JayOh Logger (v0.1 starter)

Org-local error logging, inspired by Nebula Logger's core idea: log entries
are published as a **platform event** so they survive a transaction rollback,
then persisted by a separate trigger.

## What's here
- `Log__c` — one header per transaction (grouped by `TransactionId__c`)
- `Log_Entry__c` — child records, one per log call
- `Log_Entry_Event__e` — the platform event that decouples logging from the
  transaction's success/failure
- `Log_Level_Setting__mdt` — Custom Metadata controlling minimum level per
  Permission Set / Profile / org default, plus retention days for purging
- `Logger.cls` — the class you actually call from Apex
- `LoggerInvocable.cls` — Flow (`@InvocableMethod`) and LWC/Aura
  (`@AuraEnabled`) entry points
- `LogEntryEventHandler.cls` + trigger — persists events into `Log__c`/`Log_Entry__c`
- `LogMasking.cls` — regex denylist scrubbing card numbers/SSNs/API keys before persist
- `LogPurgeBatch.cls` — scheduled batch deleting logs older than the configured retention

## Deploying to a client org
```bash
sf project deploy start --source-dir force-app -o <target-org-alias>
```

## Usage
```apex
try {
    // risky callout
} catch (Exception ex) {
    Logger.error('CBHttpClient.patchShippingAddress', 'Chargebee PATCH failed', ex);
}
Logger.flush(); // ERROR level auto-flushes; call this explicitly for INFO/DEBUG/WARN buffers
```

From Flow: use the "Log Message" invocable action.
From LWC: call the exposed `LoggerInvocable.logFromClient` via an imperative Apex call.

## Schedule the purge job (once per org)
```apex
System.schedule('JayOh Log Purge - Weekly', '0 0 2 ? * SUN', new LogPurgeBatch());
```

## v0.2 additions
- **Alerting** — `Log_Alert_Setting__mdt` toggles email (sent synchronously) and/or
  Slack (queued via `LogAlertQueueable` since callouts aren't allowed synchronously
  from a trigger) whenever an ERROR-level entry is persisted. Slack webhook URL is
  stored in plain Custom Metadata for simplicity — swap for a Named Credential
  before using this against a real client incident channel.
- **Configurable masking** — `Log_Masking_Pattern__mdt` holds active regex patterns
  (seeded with card number / SSN / API-key defaults); add client-specific patterns
  (e.g. a Chargebee key prefix) without a deploy. Falls back to built-in patterns
  if no active records exist.
- **Quiddity capture** — every entry now automatically records execution context
  (`BATCH_APEX`, `QUEUEABLE`, `FUTURE`, `AURA`, `VF`, `RUNTEST`, etc.) via
  `Request.getCurrent().getQuiddity()` — no call-site changes needed.
- **Retention export** — `Log_Level_Setting__mdt.ExportBeforePurge__c` +
  `ExportRecipientEmail__c` email a CSV of everything about to be purged, so
  ERROR history from 45 days ago isn't gone forever if a client asks about it.
- **LWC log viewer** — `logViewer` component (drop on an App Page) lists recent
  `Log__c` headers with a severity filter; click a row to expand its entries.
  Backed by `LogViewerController`.
- **Client-side logging + global JS error boundary** — `loggerClient` is a
  headless utility LWC (no UI, import its exports). Call
  `installGlobalErrorBoundary('yourAppShellName')` once from your top-level
  component to catch uncaught JS errors and unhandled promise rejections
  automatically; call `logError`/`logWarn`/`logInfo` directly for anything else.

## v0.3 additions
- **Report Type + starter reports** — `Log_And_Log_Entries` custom report type
  joins `Log__c` to its `Log_Entry__c` children. Two starter reports ship with
  it: `Recent Errors` (tabular, last 7 days) and `Errors by Source` (summary,
  grouped by `Source__c`, last 30 days) — the latter is what tells you a
  flaky integration is trending before a client raises it. Build a dashboard
  from these in-org (Setup UI is genuinely faster than hand-written dashboard
  metadata, and it needs a folder ID that only exists post-deploy anyway).
- **Packaging** — see `PACKAGING.md` for the exact `sf package create` /
  `version create` / `install` commands. Not run yet — needs your Dev Hub
  session, which this environment can't reach.

## Not built as code — do these in Setup instead
- **Dashboard** — build it in-org referencing the two reports above.

## Tests
Included: `LogLevelTest`, `LogMaskingTest`, `LogLevelSettingSelectorTest`,
`LogEntryEventHandlerTest`, `LoggerTest`, `LoggerInvocableTest`, `LogPurgeBatchTest`,
`LogAlertServiceTest`, `LogAlertQueueableTest`, `LogViewerControllerTest`.
Platform-event delivery in tests uses `Test.getEventBus().deliver()` after
`Test.stopTest()` — that's what actually fires `LogEntryEventTrigger` synchronously
during the test so the persisted `Log__c`/`Log_Entry__c` rows can be asserted on.

Run before deploying to a client org:
```bash
sf apex run test --test-level RunLocalTests --result-format human --wait 10 -o <target-org-alias>
```

## Still open
- Bulk behavior above 200 events in a single publish batch beyond what's tested here
- No test proving `LogAlertQueueable` behavior when the Slack endpoint returns a
  non-200 (currently just swallowed/logged to debug)
- `loggerClient`'s global error boundary is installed manually per app shell —
  not automatically wired into every LWC in a client org
