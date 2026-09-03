import { LightningElement, wire } from 'lwc';
import getRecentLogs from '@salesforce/apex/LogViewerController.getRecentLogs';
import getLogEntries from '@salesforce/apex/LogViewerController.getLogEntries';

const LEVEL_OPTIONS = [
    { label: 'All', value: 'ALL' },
    { label: 'Error', value: 'ERROR' },
    { label: 'Warn', value: 'WARN' },
    { label: 'Info', value: 'INFO' },
    { label: 'Debug', value: 'DEBUG' }
];

export default class LogViewer extends LightningElement {
    levelFilter = 'ALL';
    levelOptions = LEVEL_OPTIONS;
    logs = [];
    entries = [];
    selectedLogId;
    isLoading = true;

    @wire(getRecentLogs, { numRecords: 25, levelFilter: '$levelFilter' })
    wiredLogs({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.logs = data.map((log) => ({
                ...log,
                formattedDate: new Date(log.createdDate).toLocaleString(),
                severityClass: 'sev-' + (log.highestSeverity || '').toLowerCase()
            }));
        } else if (error) {
            this.logs = [];
            // eslint-disable-next-line no-console
            console.error('logViewer: failed to load logs', error);
        }
    }

    get hasLogs() {
        return this.logs && this.logs.length > 0;
    }

    handleLevelChange(event) {
        this.levelFilter = event.detail.value;
        this.selectedLogId = undefined;
        this.entries = [];
    }

    handleRowClick(event) {
        const logId = event.currentTarget.dataset.id;
        this.selectedLogId = logId;
        getLogEntries({ logId })
            .then((data) => {
                this.entries = data.map((entry, idx) => ({
                    ...entry,
                    key: logId + '-' + idx,
                    occurredAt: entry.occurredAt ? new Date(entry.occurredAt).toLocaleString() : ''
                }));
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('logViewer: failed to load entries', error);
            });
    }
}
