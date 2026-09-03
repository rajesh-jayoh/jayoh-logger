<div align="center">

# JayOh Logger

**Org-local error logging for Salesforce, built to survive the transaction that broke.**

[![Salesforce](https://img.shields.io/badge/Salesforce-Apex-00A1E0)](https://developer.salesforce.com/)
[![API Version](https://img.shields.io/badge/API-v67.0-0176D3)](sfdx-project.json)
[![License](https://img.shields.io/badge/License-Unlicense-lightgrey)](#)
[![Tests](https://img.shields.io/badge/tests-10%20classes-brightgreen)](#tests)
[![Status](https://img.shields.io/badge/status-v1.2-brightgreen)](#changelog)

*Inspired by [Nebula Logger](https://github.com/jongpie/NebulaLogger)'s core idea — reimplemented lean, and platform-event-backed from the ground up.*

</div>

---

## The core idea

If a transaction throws and rolls back, any `Log_Entry__c` you inserted earlier in that *same* transaction rolls back with it — you lose the exact error you built this to capture.

**JayOh Logger publishes every log entry as a platform event first.** Platform events commit independently of the surrounding transaction, so the entry survives even when everything else unwinds. A separate trigger then persists it into durable objects.

```mermaid
flowchart LR
    A["Apex / Flow / LWC\ncall site"] -->|"Logger.error() etc."| B["In-memory buffer"]
    B -->|"EventBus.publish()"| C(("Log_Entry_Event__e\nplatform event"))
    C -->|"survives rollback"| D["LogEntryEventTrigger"]
    D --> E[("Log__c\nheader / txn")]
    D --> F[("Log_Entry__c\nchild entries")]
    F -->|"ERROR level"| G["LogAlertService"]
    G -->|"sync"| H["Email"]
    G -->|"queued callout"| I["Slack"]

    style C fill:#cfe8fc,stroke:#0176D3,stroke-width:2px,color:#1a1a1a
    style G fill:#d9ead3,stroke:#38761d,stroke-width:2px,color:#1a1a1a
```

---

## Features

| | |
|---|---|
| **Rollback-safe logging** | Platform-event-backed persistence — `ERROR` entries survive a failed transaction |
| **Configurable levels** | Per Permission Set / Profile / org default, via Custom Metadata — no deploy to change |
| **Auto-masking** | Card numbers, SSNs, API keys scrubbed before persist; patterns are editable Custom Metadata |
| **Quiddity capture** | Every entry auto-records execution context (`BATCH_APEX`, `QUEUEABLE`, `AURA`, etc.) |
| **Alerting** | Email + Slack on `ERROR`, toggled per org |
| **Retention + export** | Scheduled purge batch, with an optional CSV email before anything's deleted |
| **LWC log viewer** | Drop-in component to browse recent logs without leaving the app |
| **Client-side capture** | Global JS error boundary for LWC — uncaught errors stop vanishing into the console |
| **Reports** | Custom report type + two starter reports (`Recent Errors`, `Errors by Source`) |
| **Flow & LWC entry points** | `@InvocableMethod` and `@AuraEnabled` — not Apex-only |

---

## What's in the package

```
force-app/main/default/
├── classes/            Logger, LoggerInvocable, LogEntryEventHandler,
│                       LogAlertService, LogMasking, LogPurgeBatch,
│                       LogViewerController, LogLevelSettingSelector …
├── triggers/           LogEntryEventTrigger  (platform event → durable objects)
├── objects/            Log__c · Log_Entry__c · Log_Entry_Event__e
│                       Log_Level_Setting__mdt · Log_Alert_Setting__mdt
│                       Log_Masking_Pattern__mdt
├── customMetadata/     Seeded defaults for the three CMDTs above
├── lwc/                logViewer (visible)  ·  loggerClient (headless utility)
├── flows/              Log_Fault_Handler (reusable Subflow for Fault Connectors)
├── reportTypes/        Log_And_Log_Entries
└── reports/            Recent Errors · Errors by Source
```

---

## Quick start

**Deploy to any org:**
```bash
sf project deploy start --source-dir force-app -o <target-org-alias>
```

**Log from Apex:**
```apex
try {
    // risky callout
} catch (Exception ex) {
    Logger.error('CBHttpClient.patchShippingAddress', 'Chargebee PATCH failed', ex);
} finally {
    Logger.flush(); // see "Governor limits" below for why this must be exactly one call, not one per error
}
```

**Log from Flow:** use the *"Log Message"* invocable action (see [Logging from Flow](#logging-from-flow) below).

**Log from LWC:**
```js
import { logError, installGlobalErrorBoundary } from 'c/loggerClient';

// one-off
logError('myComponent.handleSave', error);

// once, from your top-level component — catches uncaught errors app-wide
installGlobalErrorBoundary('myAppShell');
```

**Schedule the purge job (once per org):**
```apex
System.schedule('JayOh Log Purge - Weekly', '0 0 2 ? * SUN', new LogPurgeBatch());
```

---

## Logging from Flow

`LoggerInvocable.logFromFlow` is exposed as an invocable action labeled **"Log Message"**, available in Screen Flows, Autolaunched Flows, and Record-Triggered Flows. It takes:

| Input | Required | Notes |
|---|---|---|
| `level` | Yes | `ERROR`, `WARN`, `INFO`, or `DEBUG` |
| `source` | Yes | Free text — use the Flow's name, e.g. `Flow: Renewal_Closed_Won` |
| `message` | Yes | The text to log |
| `relatedRecordId` | No | Any record Id to link the entry to |

**Ad hoc logging inside a Flow:**

Drop the action anywhere you want a checkpoint logged — after a Get Records, before a risky Update, etc.

**Catching Flow faults (the higher-value use case):**

Flow doesn't log unhandled errors anywhere durable by default — a fault just shows the user a generic error and the transaction is gone. Wire "Log Message" into the **Fault Connector** of any element that can fail (Create/Update/Delete Records, Apex Actions, Sub-flows):

- `level`: `ERROR`
- `source`: the Flow's name (hardcode it — `$Flow.CurrentFlow` variables aren't reliably available in every context)
- `message`: `{!$Flow.FaultMessage}`

Because this goes through the same platform-event pipeline as everything else, a Flow fault logged this way survives even though the Flow's own DML rolled back — same guarantee Apex gets. This is the closest equivalent to Nebula Logger's Flow fault-handling plugin, without needing a separate subflow per Flow.

**Recommended pattern:** a ready-made reusable Subflow ships with this package — `flows/Log_Fault_Handler.flow-meta.xml`. Connect any element's Fault Connector to it and pass:

- `FaultSource`: the calling Flow's name, hardcoded (e.g. `Renewal_Closed_Won`)
- `FaultMessage`: `{!$Flow.FaultMessage}`
- `RelatedRecordId`: optional, any record Id relevant to the fault

One place to maintain across every BMG/Level Data Flow instead of repeating the action config in each one.

---

## Governor limits (why flush() works the way it does)

`EventBus.publish()` is capped at **150 calls per transaction** — a hard Apex governor limit. Critically, a single `EventBus.publish(list)` call counts as **one** call no matter how many events are in the list, the same way `Database.insert(list)` counts as one DML statement regardless of list size.

**`Logger` buffers every entry in memory and only publishes on `flush()`** — mirroring [Nebula Logger](https://github.com/jongpie/NebulaLogger)'s model. An earlier version of this class auto-flushed on every `ERROR` call individually; that meant a loop catching 200 errors made 200 separate `publish()` calls and risked the 150-per-transaction ceiling. Buffering avoids that entirely.

The trade-off: **you must call `Logger.flush()` yourself** — ideally in a `finally` block, so it still runs even when an exception propagates past your `catch`. A buffered entry that never reaches `flush()` is silently lost.

Additional controls (same names as Nebula Logger's, for anyone already familiar with it):

| Method | Behavior |
|---|---|
| `Logger.flush()` | Publish everything buffered so far as one call |
| `Logger.flushBuffer()` | Discard everything buffered, without publishing |
| `Logger.suspendSaving()` / `resumeSaving()` | Ignore log calls entirely until resumed — useful for silencing a known-noisy code path without removing call sites |
| `Logger.setSyncMode(true)` | Bypass platform events and insert `Log__c`/`Log_Entry__c` directly and synchronously — for local debugging (see the real DML error immediately) or as a fallback if your org's platform event allocation is exhausted. **Loses rollback-safety while enabled.** |

There's also a separate, **org-wide** daily/hourly limit on platform events published (varies by edition — see [Salesforce's Platform Event Limits](https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/platform_event_limits.htm)). Batching solves the per-transaction risk; it doesn't remove this ceiling. Nebula Logger's own troubleshooting docs flag the same thing — worth monitoring in a very high-volume org.

---

## Configuration (all Custom Metadata — no deploy required)

| Custom Metadata Type | Controls |
|---|---|
| `Log_Level_Setting__mdt` | Minimum log level per Permission Set/Profile/org; retention days; export-before-purge |
| `Log_Alert_Setting__mdt` | Email/Slack toggles, recipients, webhook URL |
| `Log_Masking_Pattern__mdt` | Active regex patterns scrubbed from every message before persist |

---

## Tests

10 classes, full coverage of the Apex surface:

`LogLevelTest` · `LogMaskingTest` · `LogLevelSettingSelectorTest` · `LogEntryEventHandlerTest` · `LoggerTest` · `LoggerInvocableTest` · `LogPurgeBatchTest` · `LogAlertServiceTest` · `LogAlertQueueableTest` · `LogViewerControllerTest`

> Platform-event delivery in tests uses `Test.getEventBus().deliver()` after `Test.stopTest()` — that's what fires `LogEntryEventTrigger` synchronously so persisted rows can actually be asserted on.

```bash
sf apex run test --test-level RunLocalTests --result-format human --wait 10 -o <target-org-alias>
```

---

## Packaging for multi-org use

See **[`PACKAGING.md`](PACKAGING.md)** for the full `sf package create` → `version create` → `install` walkthrough. Turning this into a versioned unlocked package means every client org installs from the same source instead of diverging hand-deployed copies.

---

## Changelog

<details open>
<summary><strong>v1.2</strong> — Fixed a governor-limit bug in Logger's flush behavior</summary>

- **Fix:** removed an auto-flush-on-every-`ERROR`-call bug that could exceed the 150-`EventBus.publish()`-calls-per-transaction limit in any loop logging many errors
- `Logger` now buffers everything and only publishes on explicit `flush()`, matching Nebula Logger's model
- Added `flushBuffer()`, `suspendSaving()`/`resumeSaving()`, and `setSyncMode()` — mirrors Nebula Logger's save-control API
- New README section: [Governor limits](#governor-limits-why-flush-works-the-way-it-does)
- **Action needed if you already deployed v1.1 or earlier:** redeploy `Logger.cls` and update any call sites to call `flush()` in a `finally` block — buffered entries are no longer auto-persisted on `ERROR`

</details>

<details>
<summary><strong>v1.1</strong> — Flow fault logging</summary>

- Expanded README section documenting the "Log Message" invocable action's inputs and how to wire it into a Flow's Fault Connector
- Reusable Subflow `Log_Fault_Handler` — connect any element's Fault Connector to it and pass the Flow's name + `{!$Flow.FaultMessage}`
- *Not covered:* no automated test — Flow behavior isn't exercised by Apex `RunLocalTests`; verify manually against a deliberately-failing element after deploying

</details>

<details>
<summary><strong>v1.0</strong> — Reports & packaging groundwork</summary>

- Custom report type `Log_And_Log_Entries` joining `Log__c` → `Log_Entry__c`
- Starter reports: `Recent Errors` (last 7 days), `Errors by Source` (last 30 days, grouped)
- `PACKAGING.md` with exact unlocked-package CLI commands
- *Not built as code:* dashboard — build in-org, since it needs a folder ID that only exists post-deploy

</details>

<details>
<summary><strong>v0.2</strong> — Alerting, masking, visibility</summary>

- **Alerting:** email (sync) + Slack (queued callout) on `ERROR`
- **Configurable masking:** patterns moved to Custom Metadata, seeded with card/SSN/API-key defaults
- **Quiddity capture:** execution context recorded automatically on every entry
- **Retention export:** CSV emailed before purge, gated by Custom Metadata
- **LWC log viewer:** browse/filter/drill into recent logs
- **Client-side capture:** headless `loggerClient` utility + global JS error boundary

</details>

<details>
<summary><strong>v0.1</strong> — Core framework</summary>

- `Log__c` / `Log_Entry__c` / `Log_Entry_Event__e` platform-event pipeline
- `Logger.cls` + `LoggerInvocable` (Flow/LWC entry points)
- Per-Permission-Set/Profile log level control
- Regex-based masking, scheduled retention purge

</details>

---

## Still open

- Bulk behavior above 200 events in a single publish batch, beyond what's tested
- No test proving `LogAlertQueueable` behavior on a non-200 Slack response (currently swallowed/logged to debug)
- Global JS error boundary is opt-in per app shell, not auto-wired into every LWC in a client org
- `Log_Fault_Handler` Flow has no automated test (Flow tests are separate from Apex `RunLocalTests` coverage) — verify manually in a sandbox after deploying, e.g. by wiring it to a deliberately-failing Fault Connector

---

<div align="center">

Built for <a href="https://jayoh.io">JayOh Consultants</a> · maintained across client engagements, not a single org

</div>
