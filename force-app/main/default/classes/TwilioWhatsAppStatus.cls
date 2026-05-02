@RestResource(urlMapping='/twilio/whatsapp/status')
global with sharing class TwilioWhatsAppStatus {

    @HttpPost
    global static void receiveStatus() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String rawBody = req.requestBody.toString();
            Map<String, String> params = parseFormBody(rawBody);

            String messageSid = params.get('MessageSid');
            String status     = params.get('MessageStatus'); // sent, delivered, failed, read
            String toNumber   = params.get('To');
            String fromNumber = params.get('From');

            System.debug('Twilio Status Callback => SID: ' + messageSid + ' Status: ' + status);

            // Find the SMS record by Twilio MessageSid and update status
            if (!String.isBlank(messageSid)) {
                List<SMS_Message__c> msgs = [
                    SELECT Id, Status__c
                    FROM SMS_Message__c
                    WHERE External_Message_Id__c = :messageSid
                    LIMIT 1
                ];

                if (!msgs.isEmpty()) {
                    // Map Twilio status to your picklist values
                    String mappedStatus = mapStatus(status);
                    msgs[0].Status__c = mappedStatus;
                    update msgs[0];
                }
            }

            // Return empty TwiML response
            res.statusCode = 200;
            res.addHeader('Content-Type', 'text/xml');
            res.responseBody = Blob.valueOf('<Response></Response>');

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(e.getMessage());
        }
    }

    // Map Twilio status → your Status__c picklist
    private static String mapStatus(String twilioStatus) {
        if (twilioStatus == null) return 'Unknown';
        switch on twilioStatus.toLowerCase() {
            when 'queued'      { return 'Sent'; }
            when 'sent'        { return 'Sent'; }
            when 'delivered'   { return 'Delivered'; }
            when 'read'        { return 'Delivered'; }
            when 'failed'      { return 'Failed'; }
            when 'undelivered' { return 'Failed'; }
            when else          { return twilioStatus; }
        }
    }

    private static Map<String, String> parseFormBody(String body) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(body)) return result;
        for (String pair : body.split('&')) {
            List<String> parts = pair.split('=', 2);
            String key = EncodingUtil.urlDecode(parts[0], 'UTF-8');
            String val = parts.size() > 1
                ? EncodingUtil.urlDecode(parts[1], 'UTF-8')
                : '';
            result.put(key, val);
        }
        return result;
    }
}