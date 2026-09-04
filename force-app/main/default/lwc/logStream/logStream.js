/**
 * Live view of Log_Entry_Event__e as they're published, using empApi to
 * subscribe directly to the platform event channel — no polling, no Apex
 * controller. Caps the visible list at 50 most-recent entries per session;
 * this is a monitoring view, not a queryable history (use logViewer or a
 * report for that).
 */
import { LightningElement } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

const CHANNEL_NAME = '/event/Log_Entry_Event__e';
const MAX_VISIBLE_ENTRIES = 50;

export default class LogStream extends LightningElement {
    entries = [];
    subscription;
    isConnected = false;

    connectedCallback() {
        subscribe(CHANNEL_NAME, -1, (message) => this.handleEvent(message)).then((sub) => {
            this.subscription = sub;
            this.isConnected = true;
        });

        onError((error) => {
            this.isConnected = false;
            // eslint-disable-next-line no-console
            console.error('logStream: empApi error', error);
        });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

    handleEvent(message) {
        const payload = message.data.payload;
        const entry = {
            key: message.data.event.replayId + '-' + payload.Source__c,
            level: payload.Level__c,
            source: payload.Source__c,
            message: payload.Message__c,
            formattedTime: payload.OccurredAt__c ? new Date(payload.OccurredAt__c).toLocaleTimeString() : '',
            severityClass: 'sev-' + (payload.Level__c || '').toLowerCase()
        };
        // Newest first, capped — this is a live view, not a full history.
        this.entries = [entry, ...this.entries].slice(0, MAX_VISIBLE_ENTRIES);
    }

    get hasEntries() {
        return this.entries.length > 0;
    }

    get statusIcon() {
        return this.isConnected ? 'utility:connected_apps' : 'utility:offline';
    }

    get statusVariant() {
        return this.isConnected ? 'success' : 'error';
    }

    get statusLabel() {
        return this.isConnected ? 'Connected — listening for new entries' : 'Not connected';
    }
}
