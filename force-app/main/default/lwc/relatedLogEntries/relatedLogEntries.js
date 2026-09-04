import { LightningElement, api, wire } from 'lwc';
import getRelatedEntries from '@salesforce/apex/RelatedLogEntriesController.getRelatedEntries';

export default class RelatedLogEntries extends LightningElement {
    @api recordId;
    @api numRecords = 20;

    entries = [];
    isLoading = true;

    @wire(getRelatedEntries, { recordId: '$recordId', numRecords: '$numRecords' })
    wiredEntries({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.entries = data.map((entry) => ({
                ...entry,
                formattedDate: entry.occurredAt ? new Date(entry.occurredAt).toLocaleString() : '',
                severityClass: 'sev-' + (entry.level || '').toLowerCase()
            }));
        } else if (error) {
            this.entries = [];
            // eslint-disable-next-line no-console
            console.error('relatedLogEntries: failed to load entries', error);
        }
    }

    get hasEntries() {
        return this.entries && this.entries.length > 0;
    }
}
