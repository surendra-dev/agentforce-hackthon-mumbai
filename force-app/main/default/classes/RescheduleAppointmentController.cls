public without sharing class RescheduleAppointmentController {

    public class Request {
        @InvocableVariable(required=false)
        public String patientName;
        
        @InvocableVariable(required=false)
        public String doctorName;

        @InvocableVariable(required=false)
        public String appointmentDate;
        
        @InvocableVariable(required=false)
        public String newDate;
        
        @InvocableVariable(required=false)
        public String newTime;
    }

    public class Response {
        @InvocableVariable
        public String displayText;
    }

    @InvocableMethod(label='Reschedule Patient Appointment' 
                     description='Reschedules existing appointment to new date/time')
    public static List<Response> rescheduleAppointment(
        List<Request> requests) {
        
        List<Response> results = new List<Response>();
        
        for (Request req : requests) {
            Response res = new Response();
            
            try {
                String nameSearch = '%' + req.patientName + '%';
                List<ServiceAppointment> appts = 
                    new List<ServiceAppointment>();

                // Search by name + date
                if (!String.isBlank(req.appointmentDate)) {
                    Date apptDate = Date.valueOf(
                        req.appointmentDate);
                    DateTime dayStart = DateTime.newInstance(
                        apptDate, Time.newInstance(0,0,0,0));
                    DateTime dayEnd = DateTime.newInstance(
                        apptDate, Time.newInstance(23,59,59,0));
                    appts = [
                        SELECT Id, Subject, Status,
                               SchedStartTime, SchedEndTime,
                               Contact.Name, Contact.Phone,
                               Contact.MobilePhone, Contact.Email,
                               Description,AppointmentNumber,
                               ServiceTerritory.Name,
                               ServiceTerritoryId
                        FROM ServiceAppointment
                        WHERE Contact.Name LIKE :nameSearch
                        AND SchedStartTime >= :dayStart
                        AND SchedStartTime <= :dayEnd
                        AND Status != 'Cancelled'
                        ORDER BY SchedStartTime ASC
                        LIMIT 1
                    ];
                }
                // Search by name + filter by doctor in Apex
                else if (!String.isBlank(req.doctorName)) {
                    List<ServiceAppointment> allAppts = [
                        SELECT Id, Subject, Status,
                               SchedStartTime, SchedEndTime,
                               Contact.Name, Contact.Phone,
                               Contact.MobilePhone, Contact.Email,
                               Description,AppointmentNumber,
                               ServiceTerritory.Name,
                               ServiceTerritoryId
                        FROM ServiceAppointment
                        WHERE Contact.Name LIKE :nameSearch
                        AND Status != 'Cancelled'
                        AND SchedStartTime > :DateTime.now()
                        ORDER BY SchedStartTime ASC
                        LIMIT 20
                    ];

                    // Filter by doctor name in Apex
                    String doctorSearch = 
                        req.doctorName.toLowerCase();
                    for (ServiceAppointment a : allAppts) {
                        if (!String.isBlank(a.Description)
                            && a.Description.toLowerCase()
                                .contains(doctorSearch)) {
                            appts.add(a);
                            break;
                        }
                    }

                    // If no match found by doctor, take first
                    if (appts.isEmpty() && !allAppts.isEmpty()) {
                        appts.add(allAppts[0]);
                    }
                }
                // Search by name only
                else {
                    appts = [
                        SELECT Id, Subject, Status,
                               SchedStartTime, SchedEndTime,
                               Contact.Name, Contact.Phone,
                               Contact.MobilePhone, Contact.Email,
                               Description,
                               ServiceTerritory.Name,AppointmentNumber,
                               ServiceTerritoryId
                        FROM ServiceAppointment
                        WHERE Contact.Name LIKE :nameSearch
                        AND Status != 'Cancelled'
                        AND SchedStartTime > :DateTime.now()
                        ORDER BY SchedStartTime ASC
                        LIMIT 1
                    ];
                }
                
                if (appts.isEmpty()) {
                    res.displayText = 
                        'No upcoming appointment found for '
                        + req.patientName + '.\n'
                        + 'Please call 1800-ONCO-CARE.';
                    results.add(res);
                    continue;
                }
                
                ServiceAppointment appt = appts[0];

                // Extract doctor name from description
                String existingDoctor = 'Your Doctor';
                if (!String.isBlank(appt.Description)) {
                    for (String line : 
                        appt.Description.split('\n')) {
                        if (line.contains('Doctor:')) {
                            existingDoctor = line
                                .replace('Doctor:', '')
                                .trim();
                            break;
                        }
                    }
                }
                
                // Parse new date/time
                DateTime newSchedStart = 
                    DateTime.now().addDays(1);
                DateTime newSchedEnd = 
                    newSchedStart.addHours(1);
                
                try {
                    String cleanTime = req.newTime
                        .replace('AM', '').replace('PM', '')
                        .replace('am', '').replace('pm', '')
                        .trim();
                    Boolean isPM = req.newTime.toUpperCase()
                        .contains('PM');
                    Boolean isAM = req.newTime.toUpperCase()
                        .contains('AM');
                    Integer hour = Integer.valueOf(
                        cleanTime.split(':')[0].trim());
                    Integer minute = cleanTime.contains(':')
                        ? Integer.valueOf(
                            cleanTime.split(':')[1].trim()) 
                        : 0;
                    if (isPM && hour != 12) hour += 12;
                    if (isAM && hour == 12) hour = 0;
                    Date parsedDate = Date.valueOf(req.newDate);
                    newSchedStart = DateTime.newInstance(
                        parsedDate,
                        Time.newInstance(hour, minute, 0, 0));
                    newSchedEnd = newSchedStart.addHours(1);
                    
                } catch(Exception dtEx) {
                    System.debug('Date parse error: ' 
                        + dtEx.getMessage());
                    newSchedStart = DateTime.now().addDays(1);
                    newSchedEnd = newSchedStart.addHours(1);
                }
                
                // Check slot availability
                List<ServiceAppointment> conflict = [
                    SELECT Id FROM ServiceAppointment
                    WHERE SchedStartTime = :newSchedStart
                    AND ServiceTerritoryId = 
                        :appt.ServiceTerritoryId
                    AND Status != 'Cancelled'
                    AND Id != :appt.Id
                    LIMIT 1
                ];
                
                if (!conflict.isEmpty()) {
                    res.displayText = 
                        'Sorry! That time slot is already '
                        + 'booked for ' + existingDoctor + '.\n'
                        + 'Please choose a different time.\n\n'
                        + 'Call 1800-ONCO-CARE for help.';
                    results.add(res);
                    continue;
                }
                
                // Store old details for confirmation
                DateTime oldStart = appt.SchedStartTime;
                String oldDateStr = oldStart.format(
                    'EEEE, MMMM d, yyyy');
                String oldTimeStr = oldStart.format('h:mm a');

                // Update appointment
                appt.SchedStartTime = newSchedStart;
                appt.SchedEndTime = newSchedEnd;
                appt.Status = 'Scheduled';
                appt.Description = 
                    (!String.isBlank(appt.Description)
                        ? appt.Description : '')
                    + '\nRescheduled from: '
                    + oldStart.format('MMM d, yyyy h:mm a')
                    + ' to: '
                    + newSchedStart.format('MMM d, yyyy h:mm a');
                update appt;
                
                String newDateStr = newSchedStart.format(
                    'EEEE, MMMM d, yyyy');
                String newTimeStr = newSchedStart.format(
                    'h:mm a');
                String hospital = appt.ServiceTerritory != null
                    ? appt.ServiceTerritory.Name
                        .replace(' Territory', '')
                    : 'Onco Global';

                res.displayText = 
                'Appointment Rescheduled Successfully!\n\n'
                + 'Appointment Number: ' + appt.AppointmentNumber + '\n'
                + 'Patient: ' + appt.Contact.Name + '\n'
                + 'Doctor: ' + existingDoctor + '\n'
                + 'Hospital: ' + hospital + '\n\n'
                + 'Previous Slot:\n'
                + '  Date: ' + oldDateStr + '\n'
                + '  Time: ' + oldTimeStr + '\n\n'
                + 'New Slot:\n'
                + '  Date: ' + newDateStr + '\n'
                + '  Time: ' + newTimeStr + '\n\n'
                + 'Please arrive 15 minutes early.\n'
                + 'Bring medical records and ID proof.';
                
                sendRescheduleNotification(appt, res.displayText);
                    
            } catch(Exception e) {
                res.displayText = 
                    'Unable to reschedule.\n'
                    + 'Please call 1800-ONCO-CARE.';
            }
            
            results.add(res);
        }
        return results;
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
    
    private static void sendRescheduleNotification(
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
                'Appointment Rescheduled - Onco Global',
                messageBody
            );
        }
    }
}