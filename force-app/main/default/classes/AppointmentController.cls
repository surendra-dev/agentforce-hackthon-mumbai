public without sharing class AppointmentController {

    public class Request {
        @InvocableVariable(required=false)
        public String patientName;
        
        @InvocableVariable(required=false)
        public String doctorName;
        
        @InvocableVariable(required=false)
        public String preferredDate;
        
        @InvocableVariable(required=false)
        public String preferredTime;
        
        @InvocableVariable(required=false)
        public String locationName;
        
        @InvocableVariable(required=false)
        public String specialtyName;
    }

    public class Response {
        @InvocableVariable
        public String displayText;
    }

    @InvocableMethod(label='Book Patient Appointment'
                     description='Books appointment for patient with doctor')
    public static List<Response> bookAppointment(
        List<Request> requests) {
        
        List<Response> results = new List<Response>();
        
        for (Request req : requests) {
            Response res = new Response();
            
            try {
                // ── Step 1: Find Patient ──────────────────────
                String patientSearch = '%' + req.patientName + '%';
                List<Contact> patients = [
                    SELECT Id, Name 
                    FROM Contact 
                    WHERE Name LIKE :patientSearch 
                    LIMIT 1
                ];
                
                Id patientContactId;
                String confirmedPatientName;
                
                if (!patients.isEmpty()) {
                    patientContactId = patients[0].Id;
                    confirmedPatientName = patients[0].Name;
                } else {
                    List<Account> personAccts = [
                        SELECT Id, Name, PersonContactId 
                        FROM Account 
                        WHERE Name LIKE :patientSearch
                        AND IsPersonAccount = TRUE 
                        LIMIT 1
                    ];
                    if (!personAccts.isEmpty()) {
                        patientContactId = 
                            personAccts[0].PersonContactId;
                        confirmedPatientName = 
                            personAccts[0].Name;
                    } else {
                        res.displayText = 
                            'Patient "' + req.patientName 
                            + '" not found in our system.\n'
                            + 'Please register first or '
                            + 'call 1800-ONCO-CARE.';
                        results.add(res);
                        continue;
                    }
                }

                // ── Step 2: Find Service Territory ────────────
                String locationToSearch = String.isBlank(
                    req.locationName) ? 'Mumbai' : req.locationName;
                String territorySearch = '%' + locationToSearch + '%';
                
                List<ServiceTerritory> territories = [
                    SELECT Id, Name 
                    FROM ServiceTerritory 
                    WHERE Name LIKE :territorySearch 
                    AND IsActive = TRUE 
                    LIMIT 1
                ];

                // ── Step 3: Find Hospital Account ─────────────
                // NEW: Link hospital account to appointment
                List<Account> hospitalAccounts = [
                    SELECT Id FROM Account
                    WHERE Name LIKE :('%Onco Global%' 
                        + locationToSearch + '%')
                    AND IsPersonAccount = FALSE
                    LIMIT 1
                ];

                // ── Step 4: Handle "Any Doctor" scenario ──────
                // NEW: If no doctor specified, find available one
                String resolvedDoctorName = req.doctorName;
                if (String.isBlank(req.doctorName) 
                    || req.doctorName.toLowerCase()
                        .contains('any')
                    || req.doctorName.toLowerCase()
                        .contains('available')
                    || req.doctorName.toLowerCase()
                        .contains('whoever')) {
                    
                    // Find first available doctor at location
                    if (!territories.isEmpty()) {
                        List<ServiceTerritoryMember> stMembers = [
                            SELECT ServiceResource.Name
                            FROM ServiceTerritoryMember
                            WHERE ServiceTerritoryId = 
                                :territories[0].Id
                            AND ServiceResource.IsActive = TRUE
                            LIMIT 1
                        ];
                        if (!stMembers.isEmpty()) {
                            resolvedDoctorName = 
                                stMembers[0].ServiceResource.Name;
                        }
                    }
                }

                // ── Step 5: Parse Date/Time ───────────────────
                DateTime schedStart = DateTime.now().addDays(1);
                DateTime schedEnd = schedStart.addHours(1);
                
                try {
                    if (!String.isBlank(req.preferredDate) 
                        && !String.isBlank(req.preferredTime)) {
                        
                        // Parse time
                        String cleanTime = req.preferredTime
                            .replace('AM', '').replace('PM', '')
                            .replace('am', '').replace('pm', '')
                            .trim();
                        Boolean isPM = req.preferredTime
                            .toUpperCase().contains('PM');
                        Boolean isAM = req.preferredTime
                            .toUpperCase().contains('AM');
                        Integer hour = Integer.valueOf(
                            cleanTime.split(':')[0].trim());
                        Integer minute = cleanTime.contains(':')
                            ? Integer.valueOf(
                                cleanTime.split(':')[1].trim()) 
                            : 0;
                        if (isPM && hour != 12) hour += 12;
                        if (isAM && hour == 12) hour = 0;
                        
                        // NEW: Parse date - handle multiple formats
                        Date parsedDate = null;
                        String dateStr = req.preferredDate.trim();
                        
                        try {
                            // Format 1: YYYY-MM-DD (standard)
                            parsedDate = Date.valueOf(dateStr);
                        } catch(Exception e1) {
                            try {
                                // Format 2: DD-MM-YYYY
                                List<String> parts = 
                                    dateStr.split('-');
                                if (parts.size() == 3 
                                    && parts[0].length() <= 2) {
                                    parsedDate = Date.newInstance(
                                        Integer.valueOf(parts[2]),
                                        Integer.valueOf(parts[1]),
                                        Integer.valueOf(parts[0])
                                    );
                                }
                            } catch(Exception e2) {
                                try {
                                    // Format 3: DD/MM/YYYY
                                    List<String> parts2 = 
                                        dateStr.split('/');
                                    if (parts2.size() == 3) {
                                        parsedDate = Date.newInstance(
                                            Integer.valueOf(parts2[2]),
                                            Integer.valueOf(parts2[1]),
                                            Integer.valueOf(parts2[0])
                                        );
                                    }
                                } catch(Exception e3) {
                                    try {
                                        // Format 4: "23 April 2026"
                                        parsedDate = Date.parse(
                                            dateStr);
                                    } catch(Exception e4) {
                                        parsedDate = 
                                            Date.today().addDays(1);
                                    }
                                }
                            }
                        }

                        if (parsedDate == null) {
                            parsedDate = Date.today().addDays(1);
                        }
                        
                        schedStart = DateTime.newInstance(
                            parsedDate,
                            Time.newInstance(hour, minute, 0, 0));
                        schedEnd = schedStart.addHours(1);
                    }
                } catch(Exception dtEx) {
                    System.debug('Date parse error: ' 
                        + dtEx.getMessage());
                    schedStart = DateTime.now().addDays(1);
                    schedEnd = schedStart.addHours(1);
                }

                // ── Step 6: Check Slot Availability ──────────
                if (!String.isBlank(resolvedDoctorName)) {
                    String doctorSearch = 
                        '%' + resolvedDoctorName + '%';
                    List<ServiceResource> resources = [
                        SELECT Id FROM ServiceResource
                        WHERE Name LIKE :doctorSearch
                        LIMIT 10
                    ];
                    Set<Id> resourceIds = new Set<Id>();
                    for (ServiceResource sr : resources) {
                        resourceIds.add(sr.Id);
                    }
                    List<ServiceTerritoryMember> members = [
                        SELECT ServiceTerritoryId
                        FROM ServiceTerritoryMember
                        WHERE ServiceResourceId IN :resourceIds
                        LIMIT 10
                    ];
                    Set<Id> territoryIds = new Set<Id>();
                    for (ServiceTerritoryMember stm : members) {
                        territoryIds.add(stm.ServiceTerritoryId);
                    }
                    if (!territoryIds.isEmpty()) {
                        List<ServiceAppointment> existingAppts = [
                            SELECT Id 
                            FROM ServiceAppointment
                            WHERE SchedStartTime = :schedStart
                            AND Status != 'Cancelled'
                            AND ServiceTerritoryId 
                                IN :territoryIds
                            LIMIT 1
                        ];
                        if (!existingAppts.isEmpty()) {
                            String available = getAvailableSlots(
                                resolvedDoctorName, 
                                String.valueOf(
                                    schedStart.date()));
                            res.displayText =
                                resolvedDoctorName
                                + ' is not available at '
                                + req.preferredTime
                                + ' on ' + req.preferredDate
                                + '.\n\n'
                                + 'Available slots:\n'
                                + available + '\n\n'
                                + 'Please choose another time.';
                            results.add(res);
                            continue;
                        }
                    }
                }

                // ── Step 7: Create Work Order ─────────────────
                WorkOrder wo = new WorkOrder(
                    Subject = (String.isBlank(req.specialtyName)
                        ? 'Oncology' : req.specialtyName)
                        + ' Consultation',
                    Description = 
                        'Patient: ' + confirmedPatientName
                        + '\nDoctor: ' + (String.isBlank(resolvedDoctorName)
                            ? 'Any Available' : resolvedDoctorName)
                        + '\nSpecialty: ' + (String.isBlank(req.specialtyName)
                            ? 'General' : req.specialtyName)
                        + '\nLocation: ' + locationToSearch,
                    Status = 'New',
                    ContactId = patientContactId,
                    ServiceTerritoryId = territories.isEmpty()
                        ? null : territories[0].Id,
                    AccountId = hospitalAccounts.isEmpty()  // ← MOVED HERE
                        ? null : hospitalAccounts[0].Id
                );
                insert wo;
                
                // ── Step 8: Create Service Appointment ────────
                ServiceAppointment appt = new ServiceAppointment(
                    Subject = (String.isBlank(req.specialtyName)
                        ? 'Oncology' : req.specialtyName)
                        + ' Consultation',
                    Description = 
                        'Patient: ' + confirmedPatientName
                        + '\nDoctor: ' + (String.isBlank(resolvedDoctorName)
                            ? 'Any Available' : resolvedDoctorName)
                        + '\nSpecialty: ' + (String.isBlank(req.specialtyName)
                            ? 'General' : req.specialtyName)
                        + '\nLocation: ' + locationToSearch,
                    Status = 'Scheduled',
                    SchedStartTime = schedStart,
                    SchedEndTime = schedEnd,
                    Duration = 1,
                    DurationType = 'Hours',
                    ContactId = patientContactId,
                    ParentRecordId = wo.Id,
                    ServiceTerritoryId = territories.isEmpty()
                        ? null : territories[0].Id
                    // AccountId REMOVED — auto-populated by Salesforce
                );
                insert appt;

				//Re-query to get auto-generated fields
                appt = [
                    SELECT Id, AppointmentNumber,
                           SchedStartTime, SchedEndTime,
                           Status, ContactId,
                           Contact.Name, Contact.Phone,
                           Contact.MobilePhone, Contact.Email
                    FROM ServiceAppointment
                    WHERE Id = :appt.Id
                    LIMIT 1
                ];

				// ── Step 9: Link Doctor as Assigned Resource ──
                Id assignedDoctorResourceId = null;
                String assignedDoctorName = resolvedDoctorName;
                
                if (!String.isBlank(resolvedDoctorName)) {
                    String doctorSearch = 
                        '%' + resolvedDoctorName + '%';
                    List<ServiceResource> doctorResources = [
                        SELECT Id, Name
                        FROM ServiceResource
                        WHERE Name LIKE :doctorSearch
                        AND IsActive = TRUE
                        LIMIT 1
                    ];
                    
                    if (!doctorResources.isEmpty()) {
                        assignedDoctorResourceId = 
                            doctorResources[0].Id;
                        assignedDoctorName = 
                            doctorResources[0].Name;
                        
                        try {
                            AssignedResource ar = 
                                new AssignedResource(
                                    ServiceAppointmentId = appt.Id,
                                    ServiceResourceId = 
                                        assignedDoctorResourceId,
                                    IsRequiredResource = true
                                );
                            insert ar;
                        } catch(Exception arEx) {
                            System.debug(
                                'AssignedResource error: ' 
                                + arEx.getMessage());
                        }
                    }
                }

                // ── Step 10: Build Confirmation ────────────────
                String dateStr2 = schedStart.format(
                    'EEEE, MMMM d, yyyy');
                String timeStr = schedStart.format('h:mm a');
                String hospitalName = territories.isEmpty()
                    ? 'Onco Global ' + locationToSearch
                    : territories[0].Name
                        .replace(' Territory', '');
                String displayDoctor = String.isBlank(
                    resolvedDoctorName)
                    ? 'Next Available Doctor'
                    : resolvedDoctorName;
                
                res.displayText =
                'APPOINTMENT CONFIRMED\n\n'
                + 'APPOINTMENT NUMBER: ' + appt.AppointmentNumber + '\n'
                + '(Please save this number)\n\n'
                + 'Patient: ' + confirmedPatientName + '\n'
                + 'Doctor: ' + displayDoctor + '\n'
                + 'Hospital: ' + hospitalName + '\n'
                + 'Date: ' + dateStr2 + '\n'
                + 'Time: ' + timeStr + '\n\n'
                + 'IMPORTANT REMINDERS : \n'
                + '- Arrive 15 minutes early\n'
                + '- Bring medical records and ID proof\n'
                + '- Helpline: 1800-ONCO-CARE\n\n'
                + 'Your Appointment Number is: ' 
                + appt.AppointmentNumber
                + '. Please save this for cancellation '
                + 'or rescheduling.';
                
                sendAppointmentNotification(appt, res.displayText);

            } catch (Exception e) {
                res.displayText =
                    'Unable to complete booking.\n'
                    + 'Please call 1800-ONCO-CARE.';
            }
            
            results.add(res);
        }
        return results;
    }

    private static String getAvailableSlots(
        String doctorName, String preferredDate) {
        
        List<String> allSlots = new List<String>{
            '09:00', '09:30', '10:00', '10:30',
            '11:00', '11:30', '14:00', '14:30',
            '15:00', '15:30', '16:00', '16:30'
        };

        String doctorSearch = '%' + doctorName + '%';
        List<ServiceResource> resources = [
            SELECT Id FROM ServiceResource
            WHERE Name LIKE :doctorSearch
            LIMIT 10
        ];
        Set<Id> resourceIds = new Set<Id>();
        for (ServiceResource sr : resources) {
            resourceIds.add(sr.Id);
        }

        List<ServiceTerritoryMember> members = [
            SELECT ServiceTerritoryId
            FROM ServiceTerritoryMember
            WHERE ServiceResourceId IN :resourceIds
            LIMIT 10
        ];
        Set<Id> territoryIds = new Set<Id>();
        for (ServiceTerritoryMember stm : members) {
            territoryIds.add(stm.ServiceTerritoryId);
        }

        if (territoryIds.isEmpty()) {
            return 'No slots found. Call 1800-ONCO-CARE.';
        }

        Date apptDate = Date.valueOf(preferredDate);
        DateTime dayStart = DateTime.newInstance(
            apptDate, Time.newInstance(0,0,0,0));
        DateTime dayEnd = DateTime.newInstance(
            apptDate, Time.newInstance(23,59,59,0));

        List<ServiceAppointment> booked = [
            SELECT SchedStartTime
            FROM ServiceAppointment
            WHERE SchedStartTime >= :dayStart
            AND SchedStartTime <= :dayEnd
            AND Status != 'Cancelled'
            AND ServiceTerritoryId IN :territoryIds
        ];

        Set<String> bookedTimes = new Set<String>();
        for (ServiceAppointment sa : booked) {
            Integer h = sa.SchedStartTime.hour();
            Integer m = sa.SchedStartTime.minute();
            bookedTimes.add(
                String.valueOf(h).leftPad(2,'0')
                + ':'
                + String.valueOf(m).leftPad(2,'0')
            );
        }

        List<String> available = new List<String>();
        for (String slot : allSlots) {
            if (!bookedTimes.contains(slot)) {
                available.add(slot);
            }
        }

        return available.isEmpty()
            ? 'No slots available for this day.'
            : String.join(available, ', ');
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
    
    private static void sendAppointmentNotification(
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
                'Appointment Confirmed - Onco Global',
                messageBody
            );
        }
    }
}