/**
 * Posts a simple Slack message via an incoming webhook URL. Queued from
 * LogAlertService because HTTP callouts aren't allowed synchronously from
 * a platform event trigger.
 */
public class LogAlertQueueable implements Queueable, Database.AllowsCallouts {

    private List<Log_Entry__c> errorEntries;
    private String webhookUrl;

    public LogAlertQueueable(List<Log_Entry__c> errorEntries, String webhookUrl) {
        this.errorEntries = errorEntries;
        this.webhookUrl = webhookUrl;
    }

    public void execute(QueueableContext ctx) {
        String text = ':rotating_light: *' + errorEntries.size() + ' error(s) logged*\n';
        Integer shown = 0;
        for (Log_Entry__c e : errorEntries) {
            if (shown >= 5) {
                text += '...and ' + (errorEntries.size() - shown) + ' more.';
                break;
            }
            text += '- `' + e.Source__c + '`: ' + e.Message__c + '\n';
            shown++;
        }

        Map<String, Object> payload = new Map<String, Object>{ 'text' => text };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(webhookUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));

        try {
            new Http().send(req);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'LogAlertQueueable Slack post failed: ' + ex.getMessage());
        }
    }
}
