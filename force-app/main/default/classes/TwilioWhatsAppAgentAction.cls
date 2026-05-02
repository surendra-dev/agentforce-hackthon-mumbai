public with sharing class TwilioWhatsAppAgentAction {
    private static final String TEST_SMS_TO_NUMBER = '+919610599748';
    private static final String TEST_SMS_FROM_NUMBER = '+18162811238';

    public class Response {
        public Boolean success;
        public Integer statusCode;
        public String messageSid;
        public String errorMessage;
    }

    @future(callout=true)
    public static void sendWhatsAppAsync(String toNumber, String messageBody) {
        sendWhatsApp(toNumber, messageBody);
        sendSms(TEST_SMS_TO_NUMBER, TEST_SMS_FROM_NUMBER, messageBody);
    }

    @future(callout=true)
    public static void sendSmsAsync(
        String toNumber,
        String fromNumber,
        String messageBody
    ) {
        sendSms(toNumber, fromNumber, messageBody);
    }

    @future(callout=true)
    public static void sendTestSmsAsync(String messageBody) {
        sendSms(TEST_SMS_TO_NUMBER, TEST_SMS_FROM_NUMBER, messageBody);
    }

    @future
    public static void sendEmailAsync(
        String toEmail,
        String subject,
        String messageBody
    ) {
        if (String.isBlank(toEmail) || String.isBlank(messageBody)) {
            return;
        }

        Messaging.SingleEmailMessage email =
            new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ toEmail });
        email.setSubject(
            String.isBlank(subject)
                ? 'Onco Global Appointment Update'
                : subject
        );
        email.setPlainTextBody(messageBody);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }

    public static Response sendSms(
        String toNumber,
        String fromNumber,
        String messageBody
    ) {
        Response r = new Response();

        try {
            if (String.isBlank(toNumber)) {
                throw new AuraHandledException('To Number is required.');
            }

            if (String.isBlank(fromNumber)) {
                throw new AuraHandledException('From Number is required.');
            }

            if (String.isBlank(messageBody)) {
                throw new AuraHandledException('Message Body is required.');
            }

            HttpRequest httpReq = buildTwilioMessageRequest(
                normalizePhoneNumber(toNumber),
                normalizePhoneNumber(fromNumber),
                messageBody
            );

            Http http = new Http();
            HttpResponse res = http.send(httpReq);

            System.debug('Twilio SMS Status Code: ' + res.getStatusCode());
            System.debug('Twilio SMS Response Body: ' + res.getBody());

            populateResponse(r, res);

        } catch (Exception e) {
            System.debug('Twilio SMS Error: ' + e.getMessage());

            r.success = false;
            r.statusCode = 500;
            r.errorMessage = e.getMessage();
        }

        return r;
    }

    public static Response sendWhatsApp(String toNumber, String messageBody) {
        Response r = new Response();

        try {
            if (String.isBlank(toNumber)) {
                throw new AuraHandledException('To Number is required.');
            }

            if (String.isBlank(messageBody)) {
                throw new AuraHandledException('Message Body is required.');
            }

            HttpRequest httpReq = buildTwilioMessageRequest(
                'whatsapp:' + normalizePhoneNumber(toNumber),
                'whatsapp:+14155238886',
                messageBody
            );


            Http http = new Http();
            HttpResponse res = http.send(httpReq);

            System.debug('Twilio Status Code: ' + res.getStatusCode());
            System.debug('Twilio Response Body: ' + res.getBody());

            populateResponse(r, res);

        } catch (Exception e) {
            System.debug('Twilio WhatsApp Error: ' + e.getMessage());

            r.success = false;
            r.statusCode = 500;
            r.errorMessage = e.getMessage();
        }

        return r;
    }

    private static HttpRequest buildTwilioMessageRequest(
        String toNumber,
        String fromNumber,
        String messageBody
    ) {
        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint('callout:Twilio_API/Messages.json');
        httpReq.setMethod('POST');
        httpReq.setHeader(
            'Content-Type',
            'application/x-www-form-urlencoded'
        );
        httpReq.setBody(
            'To=' + EncodingUtil.urlEncode(toNumber, 'UTF-8') +
            '&From=' + EncodingUtil.urlEncode(fromNumber, 'UTF-8') +
            '&Body=' + EncodingUtil.urlEncode(messageBody, 'UTF-8')
        );

        return httpReq;
    }

    private static String normalizePhoneNumber(String phone) {
        String cleanedNumber = phone.trim();

        if (cleanedNumber.startsWith('whatsapp:')) {
            cleanedNumber = cleanedNumber.replace('whatsapp:', '');
        }

        cleanedNumber = cleanedNumber.replaceAll('[^0-9+]', '');

        if (!cleanedNumber.startsWith('+') && cleanedNumber.length() == 10) {
            cleanedNumber = '+91' + cleanedNumber;
        }

        return cleanedNumber;
    }

    private static void populateResponse(Response r, HttpResponse res) {
        r.statusCode = res.getStatusCode();
        r.success = res.getStatusCode() >= 200 && res.getStatusCode() < 300;

        if (!String.isBlank(res.getBody())) {
            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            if (parsed.containsKey('sid')) {
                r.messageSid = String.valueOf(parsed.get('sid'));
            }

            if (parsed.containsKey('message')) {
                r.errorMessage = String.valueOf(parsed.get('message'));
            }
        }
    }

}