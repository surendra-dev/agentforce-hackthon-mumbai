public with sharing class TwilioGetInboundMessages {

    public class Request {
        @InvocableVariable(required=true label='Contact Phone Number'
            description='Phone number to look up messages for, e.g. +918387036734')
        public String phoneNumber;
    }

    public class Response {
        @InvocableVariable(label='Messages JSON')
        public String messagesJson;

        @InvocableVariable(label='Message Count')
        public Integer messageCount;
    }

    @InvocableMethod(
        label='Get Inbound WhatsApp Messages'
        description='Retrieves recent inbound WhatsApp messages from a customer'
    )
    public static List<Response> getMessages(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            Response r = new Response();
            try {
                List<SMS_Message__c> msgs = [
                    SELECT From_Number__c, Message_Body__c, 
                           CreatedDate, Status__c, Direction__c
                    FROM SMS_Message__c
                    WHERE From_Number__c = :req.phoneNumber
                    AND Direction__c = 'Inbound'
                    ORDER BY CreatedDate DESC
                    LIMIT 10
                ];

                r.messageCount  = msgs.size();
                r.messagesJson  = JSON.serialize(msgs);
            } catch (Exception e) {
                r.messageCount  = 0;
                r.messagesJson  = e.getMessage();
            }

            responses.add(r);
        }

        return responses;
    }
}