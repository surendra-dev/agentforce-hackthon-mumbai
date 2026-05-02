public without sharing class CancelAppointmentController {
    
    public class Request {
        @InvocableVariable(required=false)
        public String patientName;
        
        @InvocableVariable(required=false)
        public String doctorName;
        
        @InvocableVariable(required=false)
        public String appointmentDate;
        
        @InvocableVariable(required=false)
        public String cancellationReason;
    }
    
    public class Response {
        @InvocableVariable
        public String displayText;
    }
    
    @InvocableMethod(label='Cancel Patient Appointment'
                     description='Cancels existing appointment by patient name and details')
    public static List<Response> cancelAppointment(
        List<Request> requests) {
            
            List<Response> results = new List<Response>();
            
            for (Request req : requests) {
                Response res = new Response();
                
                try {
                    String nameSearch = '%' + req.patientName + '%';
                    List<ServiceAppointment> appts = 
                        new List<ServiceAppointment>();
                    
                    // Search by name + date if provided
                    if (!String.isBlank(req.appointmentDate)) {
                        Date apptDate = Date.valueOf(
                            req.appointmentDate);
                        DateTime dayStart = DateTime.newInstance(
                            apptDate, Time.newInstance(0,0,0,0));
                        DateTime dayEnd = DateTime.newInstance(
                            apptDate, Time.newInstance(23,59,59,0));
                        appts = [
                            SELECT Id, Subject, Status,
                            SchedStartTime, Description,
                            Contact.Name, Contact.Phone,
                            Contact.MobilePhone, Contact.Email,
                            AppointmentNumber,
                            ServiceTerritory.Name
                            FROM ServiceAppointment
                            WHERE Contact.Name LIKE :nameSearch
                            AND SchedStartTime >= :dayStart
                            AND SchedStartTime <= :dayEnd
                            AND Status != 'Cancelled'
                            ORDER BY SchedStartTime ASC
                            LIMIT 5
                        ];
                    }
                    // Search by name only — get all upcoming
                    else {
                        List<ServiceAppointment> allAppts = [
                            SELECT Id, Subject, Status,
                            SchedStartTime, Description,
                            Contact.Name, Contact.Phone,
                            Contact.MobilePhone, Contact.Email,
                            AppointmentNumber,
                            ServiceTerritory.Name
                            FROM ServiceAppointment
                            WHERE Contact.Name LIKE :nameSearch
                            AND Status != 'Cancelled'
                            AND SchedStartTime > :DateTime.now()
                            ORDER BY SchedStartTime ASC
                            LIMIT 20
                        ];
                        
                        // Filter by doctor name in Apex
                        if (!String.isBlank(req.doctorName)) {
                            String doctorSearch = 
                                req.doctorName.toLowerCase();
                            for (ServiceAppointment a : allAppts) {
                                if (!String.isBlank(a.Description)
                                    && a.Description.toLowerCase()
                                    .contains(doctorSearch)) {
                                        appts.add(a);
                                    }
                            }
                        } else {
                            appts = allAppts;
                        }
                    }
                    
                    if (appts.isEmpty()) {
                        res.displayText = 
                            'No upcoming appointments found for '
                            + req.patientName + '.\n'
                            + 'Please call 1800-ONCO-CARE for help.';
                        results.add(res);
                        continue;
                    }
                    
                    // Multiple found — list them
                    if (appts.size() > 1) {
                        String apptList = 
                            'Found multiple appointments for '
                            + req.patientName + ':\n\n';
                        Integer count = 1;
                        for (ServiceAppointment a : appts) {
                            String doctor = getDoctorFromDesc(
                                a.Description);
                            String dateStr = a.SchedStartTime
                                .format('EEE, MMM d yyyy');
                            String timeStr = a.SchedStartTime
                                .format('h:mm a');
                            apptList += count + '. ' + doctor 
                                + '\n   ' + dateStr 
                                + ' at ' + timeStr + '\n\n';
                            count++;
                        }
                        apptList += 'Please specify which appointment '
                            + 'to cancel by mentioning the doctor '
                            + 'name or date.';
                        res.displayText = apptList;
                        results.add(res);
                        continue;
                    }
                    
                    // Single appointment — cancel it
                    ServiceAppointment appt = appts[0];
                    String doctor = getDoctorFromDesc(
                        appt.Description);
                    String dateStr = appt.SchedStartTime.format(
                        'EEEE, MMMM d, yyyy');
                    String timeStr = appt.SchedStartTime.format(
                        'h:mm a');
                    String hospital = appt.ServiceTerritory != null
                        ? appt.ServiceTerritory.Name
                        .replace(' Territory', '')
                        : 'Onco Global';
                    
                    appt.Status = 'Cancelled';
                    appt.Description = (appt.Description != null
                                        ? appt.Description : '')
                        + '\nCancelled by patient. Reason: '
                        + (String.isBlank(req.cancellationReason)
                           ? 'Patient request'
                           : req.cancellationReason);
                    update appt;
                    
                    res.displayText =
                        'Appointment Cancelled Successfully!\n\n'
                        + 'Appointment Number: ' + appt.AppointmentNumber + '\n'
                        + 'Patient: ' + appt.Contact.Name + '\n'
                        + 'Doctor: ' + doctor + '\n'
                        + 'Date: ' + dateStr + '\n'
                        + 'Time: ' + timeStr + '\n'
                        + 'Hospital: ' + hospital + '\n\n'
                        + 'Call 1800-ONCO-CARE to rebook anytime.';
                    
                    sendCancellationNotification(appt, res.displayText);
                    
                } catch(Exception e) {
                    res.displayText =
                        'Unable to cancel appointment.\n'
                        + 'Please call 1800-ONCO-CARE for assistance.';
                }
                
                results.add(res);
            }
            return results;
        }
    
    private static String getDoctorFromDesc(
        String description) {
            if (String.isBlank(description)) return 'Your Doctor';
            for (String line : description.split('\n')) {
                if (line.contains('Doctor:')) {
                    return line.replace('Doctor:', '').trim();
                }
            }
            return 'Your Doctor';
        }
    private static String normalizeWhatsAppNumber(String phone) {
        if (String.isBlank(phone)) return null;
        
        String cleaned = phone.trim();
        
        if (cleaned.startsWith('whatsapp:')) {
            cleaned = cleaned.replace('whatsapp:', '');
        }
        
        cleaned = cleaned.replaceAll('[^0-9+]', '');
        
        if (cleaned.startsWith('+')) {
            return cleaned;
        }
        
        if (cleaned.length() == 10) {
            return '+91' + cleaned;
        }
        
        return cleaned;
    }
    
    
    private static void sendCancellationNotification(
        ServiceAppointment appt,
        String messageBody
    ) {
        String toNumber = null;
        String toEmail = null;
        
        if (appt.Contact != null) {
            toNumber = !String.isBlank(appt.Contact.MobilePhone)
                ? appt.Contact.MobilePhone
                : appt.Contact.Phone;
            toEmail = appt.Contact.Email;
        }
        
        toNumber = normalizeWhatsAppNumber(toNumber);
        
        if (!String.isBlank(toNumber)) {
            TwilioWhatsAppAgentAction.sendWhatsAppAsync(
                toNumber,
                messageBody
            );
        }

        if (!String.isBlank(toEmail)) {
            TwilioWhatsAppAgentAction.sendEmailAsync(
                toEmail,
                'Appointment Cancelled - Onco Global',
                messageBody
            );
        }
    }
    
}