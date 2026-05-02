@RestResource(urlMapping='/twilio/whatsapp/inbound')
global with sharing class TwilioWhatsAppInbound {

    @HttpPost
    global static void receiveMessage() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            // Parse Twilio's form-encoded body
            String rawBody = req.requestBody.toString();
            Map<String, String> params = parseFormBody(rawBody);

            String fromWho       = params.get('From');       // whatsapp:+918387036734
            String to         = params.get('To');         // whatsapp:+14155238886
            String body       = params.get('Body');       // message text
            String messageSid = params.get('MessageSid'); // Twilio unique ID

            // Clean number (remove whatsapp: prefix)
            String fromNumber = fromWho.replace('whatsapp:', '');

            // Find matching Contact by phone
            List<Contact> contacts = [
                SELECT Id, Name, Phone, MobilePhone
                FROM Contact
                WHERE Phone = :fromNumber
                OR MobilePhone = :fromNumber
                LIMIT 1
            ];

            // Create SMS/WhatsApp message log record
            SMS_Message__c msg = new SMS_Message__c();
            msg.External_Message_Id__c = messageSid;
            msg.Direction__c           = 'Inbound';
            msg.From_Number__c         = fromNumber;
            msg.To_Number__c           = to.replace('whatsapp:', '');
            msg.Message_Body__c        = body;
            msg.Status__c              = 'Received';
            msg.Channel__c             = 'WhatsApp';

            if (!contacts.isEmpty()) {
                msg.Related_Contact__c = contacts[0].Id;
            }

            insert msg;

            // Return empty TwiML so Twilio doesn't retry
            res.statusCode = 200;
            res.addHeader('Content-Type', 'text/xml');
            res.responseBody = Blob.valueOf('<Response></Response>');

        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(e.getMessage());
        }
    }

    // Helper: parse application/x-www-form-urlencoded
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