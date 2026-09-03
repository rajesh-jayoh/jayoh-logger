/**
 * Utility module (not a visual component) for logging from LWC/Aura.
 * Import the `logError`/`logToServer` functions directly — this component
 * has no UI and never needs to be placed on a page itself.
 *
 * Usage in another component:
 *   import { logError, installGlobalErrorBoundary } from 'c/loggerClient';
 *
 *   // one-off:
 *   logError('myComponent.handleSave', error);
 *
 *   // app-wide, call once from your top-level/shell component's connectedCallback:
 *   installGlobalErrorBoundary('myAppShell');
 */
import logFromClient from '@salesforce/apex/LoggerInvocable.logFromClient';

export function logError(source, error, relatedRecordId) {
    const message = extractMessage(error);
    return logFromClient({ level: 'ERROR', source, message, relatedRecordId: relatedRecordId || null }).catch((e) => {
        // Never let a logging failure surface to the user or break the caller's flow.
        // eslint-disable-next-line no-console
        console.error('loggerClient: failed to log to server', e);
    });
}

export function logWarn(source, message, relatedRecordId) {
    return logFromClient({ level: 'WARN', source, message, relatedRecordId: relatedRecordId || null }).catch(() => {});
}

export function logInfo(source, message, relatedRecordId) {
    return logFromClient({ level: 'INFO', source, message, relatedRecordId: relatedRecordId || null }).catch(() => {});
}

/**
 * Wires window-level 'error' and 'unhandledrejection' listeners so
 * uncaught JS errors anywhere in the app get logged instead of only
 * appearing in the browser console. Call once, from a single top-level
 * component (e.g. your Experience Cloud/App page shell) — calling it from
 * every component would attach duplicate listeners.
 */
let boundaryInstalled = false;

export function installGlobalErrorBoundary(sourceLabel) {
    if (boundaryInstalled) {
        return;
    }
    boundaryInstalled = true;

    window.addEventListener('error', (event) => {
        logError(sourceLabel + ':window.onerror', event.error || event.message);
    });

    window.addEventListener('unhandledrejection', (event) => {
        logError(sourceLabel + ':unhandledrejection', event.reason);
    });
}

function extractMessage(error) {
    if (!error) {
        return 'Unknown error';
    }
    if (typeof error === 'string') {
        return error;
    }
    if (error.body && error.body.message) {
        return error.body.message; // typical Apex-imperative-call shape
    }
    if (error.message) {
        return error.message;
    }
    try {
        return JSON.stringify(error);
    } catch (e) {
        return String(error);
    }
}
