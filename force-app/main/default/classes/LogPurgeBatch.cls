/**
 * Deletes Log__c (and cascades to Log_Entry__c via master-detail) older than
 * the configured retention window. Retention days, and whether to email a
 * CSV export before deleting, are read from the 'Default' Log_Level_Setting__mdt
 * record so it's configurable per org without a deploy.
 *
 * Schedule weekly, e.g.:
 *   System.schedule('JayOh Log Purge - Weekly', '0 0 2 ? * SUN', new LogPurgeBatch());
 */
public class LogPurgeBatch implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new LogPurgeBatch(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Integer retentionDays = getRetentionDays();
        DateTime cutoff = System.now().addDays(-retentionDays);
        return Database.getQueryLocator([
            SELECT Id, Name, TransactionId__c, HighestSeverity__c, CreatedDate,
                   (SELECT Level__c, Source__c, Message__c, ExceptionType__c, OccurredAt__c FROM Log_Entries__r)
            FROM Log__c
            WHERE CreatedDate < :cutoff
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Log__c> logsToDelete = (List<Log__c>) scope;

        if (shouldExportBeforePurge()) {
            String recipient = getExportRecipient();
            if (String.isNotBlank(recipient)) {
                sendCsvExport(logsToDelete, recipient);
            }
        }

        delete logsToDelete;
    }

    public void finish(Database.BatchableContext bc) {
        // Intentionally no logging here to avoid a purge job logging about itself indefinitely.
    }

    private void sendCsvExport(List<Log__c> logs, String recipient) {
        try {
            String csv = 'Transaction Id,Highest Severity,Log Created,Entry Level,Entry Source,Entry Message,Exception Type,Occurred At\n';
            for (Log__c log : logs) {
                List<Log_Entry__c> childEntries = log.Log_Entries__r;
                if (childEntries.isEmpty()) {
                    csv += csvRow(log, null);
                } else {
                    for (Log_Entry__c entry : childEntries) {
                        csv += csvRow(log, entry);
                    }
                }
            }

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('log-export-' + Date.today().format() + '.csv');
            attachment.setBody(Blob.valueOf(csv));
            attachment.setContentType('text/csv');

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ recipient });
            mail.setSubject('[JayOh Logger] Archive of ' + logs.size() + ' log(s) before purge');
            mail.setPlainTextBody('Attached: CSV export of logs about to be purged for exceeding the retention window.');
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'LogPurgeBatch export failed, proceeding with delete anyway: ' + ex.getMessage());
        }
    }

    private String csvRow(Log__c log, Log_Entry__c entry) {
        List<String> fields = new List<String>{
            csvEscape(log.TransactionId__c),
            csvEscape(log.HighestSeverity__c),
            csvEscape(String.valueOf(log.CreatedDate)),
            entry == null ? '' : csvEscape(entry.Level__c),
            entry == null ? '' : csvEscape(entry.Source__c),
            entry == null ? '' : csvEscape(entry.Message__c),
            entry == null ? '' : csvEscape(entry.ExceptionType__c),
            entry == null ? '' : csvEscape(String.valueOf(entry.OccurredAt__c))
        };
        return String.join(fields, ',') + '\n';
    }

    private String csvEscape(String value) {
        if (value == null) {
            return '';
        }
        return '"' + value.replace('"', '""') + '"';
    }

    @TestVisible
    private static Log_Level_Setting__mdt mockDefaultSetting = null;

    private Log_Level_Setting__mdt getDefaultSetting() {
        if (mockDefaultSetting != null) {
            return mockDefaultSetting;
        }
        List<Log_Level_Setting__mdt> settings = [
            SELECT RetentionDays__c, ExportBeforePurge__c, ExportRecipientEmail__c
            FROM Log_Level_Setting__mdt
            WHERE DeveloperName = 'Default'
        ];
        return settings.isEmpty() ? null : settings[0];
    }

    private Integer getRetentionDays() {
        Log_Level_Setting__mdt setting = getDefaultSetting();
        if (setting != null && setting.RetentionDays__c != null) {
            return Integer.valueOf(setting.RetentionDays__c);
        }
        return 30; // sensible default if no config exists yet
    }

    private Boolean shouldExportBeforePurge() {
        Log_Level_Setting__mdt setting = getDefaultSetting();
        return setting != null && setting.ExportBeforePurge__c == true;
    }

    private String getExportRecipient() {
        Log_Level_Setting__mdt setting = getDefaultSetting();
        return setting == null ? null : setting.ExportRecipientEmail__c;
    }
}
