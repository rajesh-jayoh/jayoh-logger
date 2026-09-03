/**
 * Backs Logger.SaveMethod.REST — inserts Log__c/Log_Entry__c via a
 * synchronous callout to this org's own REST API, using the current user's
 * session ID, instead of a local DML statement. Useful in contexts where a
 * DML statement isn't available or safe to issue directly (e.g. you're
 * already deep into mixed-DML territory, or logging from a context that
 * restricts direct DML but permits callouts).
 *
 * EXPERIMENTAL — unlike the other three save methods, this one could not be
 * verified against a live org from this environment (it requires a Remote
 * Site Setting for the org's own domain, which is org-specific and only
 * knowable post-deploy). Before relying on this in production:
 *   1. Deploy this package.
 *   2. Add a Remote Site Setting whose URL is System.URL.getOrgDomainUrl()
 *      for this org (Setup > Remote Site Settings).
 *   3. Call Logger.saveLog(Logger.SaveMethod.REST) in a sandbox and confirm
 *      a Log__c/Log_Entry__c actually appears.
 * Uses PATCH-based upsert on Log__c.TransactionId__c (marked as an external
 * ID field) so repeated calls for the same transaction don't create
 * duplicate headers, matching the same idempotency behavior as the
 * EVENT_BUS/SYNCHRONOUS_DML paths.
 */
public without sharing class LogRestSaver {

    public static void save(List<Log_Entry_Event__e> events) {
        Map<String, List<Log_Entry_Event__e>> eventsByTxnId = new Map<String, List<Log_Entry_Event__e>>();
        for (Log_Entry_Event__e e : events) {
            if (!eventsByTxnId.containsKey(e.TransactionId__c)) {
                eventsByTxnId.put(e.TransactionId__c, new List<Log_Entry_Event__e>());
            }
            eventsByTxnId.get(e.TransactionId__c).add(e);
        }

        String baseUrl = System.URL.getOrgDomainUrl().toExternalForm();
        String sessionId = UserInfo.getSessionId();

        for (String txnId : eventsByTxnId.keySet()) {
            List<Log_Entry_Event__e> txnEvents = eventsByTxnId.get(txnId);
            String highestSeverity = 'INFO';
            for (Log_Entry_Event__e e : txnEvents) {
                if (LogLevel.ordinalOf(e.Level__c) > LogLevel.ordinalOf(highestSeverity)) {
                    highestSeverity = e.Level__c;
                }
            }

            Id headerId = upsertLogHeader(baseUrl, sessionId, txnId, highestSeverity);
            if (headerId == null) {
                continue; // upsert failed — skip this transaction's entries rather than throwing and losing the rest
            }
            for (Log_Entry_Event__e e : txnEvents) {
                insertLogEntry(baseUrl, sessionId, headerId, e);
            }
        }
    }

    private static Id upsertLogHeader(String baseUrl, String sessionId, String txnId, String highestSeverity) {
        Map<String, Object> body = new Map<String, Object>{
            'HighestSeverity__c' => highestSeverity
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/services/data/v61.0/sobjects/Log__c/TransactionId__c/' + EncodingUtil.urlEncode(txnId, 'UTF-8'));
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));

        try {
            HttpResponse res = new Http().send(req);
            // 201 Created (new record) returns the Id in the body; 204 No Content (updated existing) does not.
            if (res.getStatusCode() == 201) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return (Id) parsed.get('id');
            }
            if (res.getStatusCode() == 204) {
                return queryHeaderId(baseUrl, sessionId, txnId);
            }
            System.debug(LoggingLevel.WARN, 'LogRestSaver: unexpected status upserting Log__c: ' + res.getStatusCode() + ' ' + res.getBody());
            return null;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'LogRestSaver: upsert callout failed: ' + ex.getMessage());
            return null;
        }
    }

    private static Id queryHeaderId(String baseUrl, String sessionId, String txnId) {
        HttpRequest req = new HttpRequest();
        String query = 'SELECT Id FROM Log__c WHERE TransactionId__c = \'' + String.escapeSingleQuotes(txnId) + '\'';
        req.setEndpoint(baseUrl + '/services/data/v61.0/query?q=' + EncodingUtil.urlEncode(query, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + sessionId);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                return null;
            }
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> records = (List<Object>) parsed.get('records');
            if (records.isEmpty()) {
                return null;
            }
            return (Id) ((Map<String, Object>) records[0]).get('Id');
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'LogRestSaver: header lookup callout failed: ' + ex.getMessage());
            return null;
        }
    }

    private static void insertLogEntry(String baseUrl, String sessionId, Id headerId, Log_Entry_Event__e e) {
        Map<String, Object> body = new Map<String, Object>{
            'Log__c'             => headerId,
            'Level__c'           => e.Level__c,
            'Source__c'          => e.Source__c,
            'Message__c'         => e.Message__c,
            'ExceptionType__c'   => e.ExceptionType__c,
            'ExceptionMessage__c' => e.ExceptionMessage__c,
            'StackTrace__c'      => e.StackTrace__c,
            'RelatedRecordId__c' => e.RelatedRecordId__c,
            'OccurredAt__c'      => e.OccurredAt__c,
            'RunningUser__c'     => e.RunningUser__c,
            'Quiddity__c'        => e.Quiddity__c,
            'Tags__c'            => e.Tags__c
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + '/services/data/v61.0/sobjects/Log_Entry__c');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));

        try {
            new Http().send(req);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'LogRestSaver: entry insert callout failed: ' + ex.getMessage());
        }
    }
}
