/**
 * Best-effort alerting for ERROR-level log entries. Called from
 * LogEntryEventHandler after Log_Entry__c rows are inserted.
 *
 * Email is sent synchronously (Messaging.sendEmail is not a callout, so it's
 * allowed directly in the platform-event trigger context). Slack requires an
 * HTTP callout, which is NOT allowed synchronously from a trigger — that's
 * queued via LogAlertQueueable instead.
 *
 * Failures here are swallowed (logged to debug only) so a broken alert
 * channel never breaks the logging pipeline itself.
 */
public without sharing class LogAlertService {

    public static void notifyOnErrors(List<Log_Entry__c> errorEntries) {
        if (errorEntries.isEmpty()) {
            return;
        }

        Log_Alert_Setting__mdt settings = getSettings();
        if (settings == null) {
            return;
        }

        if (settings.EmailEnabled__c && String.isNotBlank(settings.EmailRecipients__c)) {
            sendEmailAlert(errorEntries, settings.EmailRecipients__c);
        }

        if (settings.SlackEnabled__c && String.isNotBlank(settings.SlackWebhookUrl__c)) {
            // Queue rather than call out directly — platform event triggers
            // (and this runs inside one) cannot make synchronous callouts.
            if (!System.isBatch() && !System.isFuture() && !System.isQueueable()) {
                System.enqueueJob(new LogAlertQueueable(errorEntries, settings.SlackWebhookUrl__c));
            }
        }
    }

    private static void sendEmailAlert(List<Log_Entry__c> errorEntries, String recipientsCsv) {
        try {
            List<String> toAddresses = recipientsCsv.split(',');
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSubject('[JayOh Logger] ' + errorEntries.size() + ' error(s) logged');
            mail.setPlainTextBody(buildEmailBody(errorEntries));
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'LogAlertService email send failed: ' + ex.getMessage());
        }
    }

    private static String buildEmailBody(List<Log_Entry__c> errorEntries) {
        String body = 'The following error(s) were logged:\n\n';
        for (Log_Entry__c e : errorEntries) {
            body += '- [' + e.Source__c + '] ' + e.Message__c;
            if (String.isNotBlank(e.ExceptionType__c)) {
                body += ' (' + e.ExceptionType__c + ')';
            }
            body += '\n';
        }
        return body;
    }

    @TestVisible
    private static Log_Alert_Setting__mdt mockSettings = null;

    private static Log_Alert_Setting__mdt getSettings() {
        if (mockSettings != null) {
            return mockSettings;
        }
        List<Log_Alert_Setting__mdt> settings = [
            SELECT EmailEnabled__c, EmailRecipients__c, SlackEnabled__c, SlackWebhookUrl__c
            FROM Log_Alert_Setting__mdt
            WHERE DeveloperName = 'Default'
        ];
        return settings.isEmpty() ? null : settings[0];
    }
}
