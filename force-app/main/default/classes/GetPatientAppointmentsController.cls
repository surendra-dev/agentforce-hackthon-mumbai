public without sharing class GetPatientAppointmentsController {

    public class Request {
        @InvocableVariable(required=false)
        public String patientName;
        
        @InvocableVariable(required=false)
        public String appointmentType; 
        // "upcoming", "past", "all"
    }

    public class Response {
        @InvocableVariable
        public String displayText;
    }

    @InvocableMethod(label='Get Patient Appointments'
                     description='Retrieves upcoming or past appointments for a patient')
    public static List<Response> getAppointments(
        List<Request> requests) {

        List<Response> results = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();

            try {
                // Validate input
                if (String.isBlank(req.patientName)) {
                    res.displayText = 
                        'Please provide patient name '
                        + 'to fetch appointments.';
                    results.add(res);
                    continue;
                }

                String nameSearch = 
                    '%' + req.patientName + '%';
                String type = String.isBlank(
                    req.appointmentType)
                    ? 'upcoming' 
                    : req.appointmentType.toLowerCase();

                // ── Find Patient Contact ───────────────────────
                List<Contact> patients = [
                    SELECT Id, Name
                    FROM Contact
                    WHERE Name LIKE :nameSearch
                    LIMIT 1
                ];

                Id patientContactId;
                String patientName;

                if (!patients.isEmpty()) {
                    patientContactId = patients[0].Id;
                    patientName = patients[0].Name;
                } else {
                    // Try Person Account
                    List<Account> personAccts = [
                        SELECT Id, Name, PersonContactId
                        FROM Account
                        WHERE Name LIKE :nameSearch
                        AND IsPersonAccount = TRUE
                        LIMIT 1
                    ];
                    if (!personAccts.isEmpty()) {
                        patientContactId = 
                            personAccts[0].PersonContactId;
                        patientName = personAccts[0].Name;
                    } else {
                        res.displayText =
                            'Patient "' + req.patientName
                            + '" not found in our system.\n'
                            + 'Please check the name and '
                            + 'try again.';
                        results.add(res);
                        continue;
                    }
                }

                // ── Query Appointments Based on Type ──────────
                List<ServiceAppointment> appointments;

                if (type == 'past') {
                    appointments = [
                        SELECT Id, AppointmentNumber,
                               SchedStartTime, SchedEndTime,
                               Status, Description,
                               ServiceTerritory.Name
                        FROM ServiceAppointment
                        WHERE ContactId = :patientContactId
                        AND SchedStartTime < :DateTime.now()
                        AND Status != 'Cancelled'
                        ORDER BY SchedStartTime DESC
                        LIMIT 5
                    ];
                } else if (type == 'all') {
                    appointments = [
                        SELECT Id, AppointmentNumber,
                               SchedStartTime, SchedEndTime,
                               Status, Description,
                               ServiceTerritory.Name
                        FROM ServiceAppointment
                        WHERE ContactId = :patientContactId
                        ORDER BY SchedStartTime DESC
                        LIMIT 10
                    ];
                } else {
                    // Default: upcoming
                    appointments = [
                        SELECT Id, AppointmentNumber,
                               SchedStartTime, SchedEndTime,
                               Status, Description,
                               ServiceTerritory.Name
                        FROM ServiceAppointment
                        WHERE ContactId = :patientContactId
                        AND SchedStartTime > :DateTime.now()
                        AND Status != 'Cancelled'
                        ORDER BY SchedStartTime ASC
                        LIMIT 5
                    ];
                }

                // No appointments found
                if (appointments.isEmpty()) {
                    String typeLabel = 
                        type == 'past' ? 'past' 
                        : type == 'all' ? '' 
                        : 'upcoming';
                    res.displayText =
                        'No ' + typeLabel 
                        + ' appointments found for '
                        + patientName + '.\n\n'
                        + 'Would you like to book '
                        + 'a new appointment?';
                    results.add(res);
                    continue;
                }

                // ── Fetch Assigned Doctors ─────────────────────
                // Collect all appointment IDs
                Set<Id> apptIds = new Set<Id>();
                for (ServiceAppointment sa : appointments) {
                    apptIds.add(sa.Id);
                }

                // Get doctors from AssignedResource
                // (proper relationship — not Description text)
                Map<Id, String> apptDoctorMap = 
                    new Map<Id, String>();

                List<AssignedResource> assignedDoctors = [
                    SELECT ServiceAppointmentId,
                           ServiceResource.Name
                    FROM AssignedResource
                    WHERE ServiceAppointmentId IN :apptIds
                    LIMIT 50
                ];

                for (AssignedResource ar : assignedDoctors) {
                    apptDoctorMap.put(
                        ar.ServiceAppointmentId,
                        ar.ServiceResource.Name
                    );
                }

                // ── Build Response ─────────────────────────────
                String typeHeader = 
                    type == 'past' 
                        ? 'Past Appointments' 
                        : type == 'all' 
                            ? 'All Appointments'
                            : 'Upcoming Appointments';

                String response = 
                    typeHeader + ' for ' 
                    + patientName + ':\n\n';

                Integer count = 1;
                for (ServiceAppointment sa : appointments) {

                    // ── Get Doctor from AssignedResource ───────
                    // Primary source: AssignedResource (proper)
                    // Fallback: Description text (legacy)
                    String doctor;
                    if (apptDoctorMap.containsKey(sa.Id)) {
                        doctor = apptDoctorMap.get(sa.Id);
                    } else {
                        // Fallback to Description parsing
                        doctor = 'Not Assigned';
                        if (!String.isBlank(sa.Description)) {
                            for (String line : 
                                sa.Description.split('\n')) {
                                if (line.contains('Doctor:')) {
                                    String parsed = line
                                        .replace('Doctor:', '')
                                        .trim();
                                    if (!String.isBlank(parsed)
                                        && parsed != 'Any Available') {
                                        doctor = parsed;
                                    }
                                    break;
                                }
                            }
                        }
                    }

                    // ── Get Specialty from Description ─────────
                    String specialty = '';
                    String location = '';
                    if (!String.isBlank(sa.Description)) {
                        for (String line : 
                            sa.Description.split('\n')) {
                            if (line.contains('Specialty:')) {
                                specialty = line
                                    .replace('Specialty:', '')
                                    .trim();
                            }
                            if (line.contains('Location:')) {
                                location = line
                                    .replace('Location:', '')
                                    .trim();
                            }
                        }
                    }

                    // ── Get Hospital Name ──────────────────────
                    String hospital = 
                        sa.ServiceTerritory != null
                        ? sa.ServiceTerritory.Name
                            .replace(' Territory', '')
                        : (!String.isBlank(location)
                            ? 'Onco Global ' + location
                            : 'Onco Global');

                    // ── Format Date and Time ───────────────────
                    String dateStr = sa.SchedStartTime
                        .format('EEEE, MMMM d, yyyy');
                    String timeStr = sa.SchedStartTime
                        .format('h:mm a');

                    // ── Status Label ───────────────────────────
                    String statusLabel = 
                        sa.Status == 'Scheduled' 
                            ? 'Scheduled'
                        : sa.Status == 'Completed' 
                            ? 'Completed'
                        : sa.Status == 'Cancelled' 
                            ? 'Cancelled'
                        : sa.Status;

                    // ── Build Each Appointment Block ───────────
                    response += 
                        count + '. Appointment : ' 
                        + sa.AppointmentNumber + '\n'
                        + '   Status     : ' 
                        + statusLabel + '\n'
                        + '   Doctor     : ' 
                        + doctor + '\n'
                        + (!String.isBlank(specialty)
                            ? '   Specialty  : ' 
                                + specialty + '\n' 
                            : '')
                        + '   Hospital   : ' 
                        + hospital + '\n'
                        + '   Date       : ' 
                        + dateStr + '\n'
                        + '   Time       : ' 
                        + timeStr + '\n\n';

                    count++;
                }

                // ── Add Options at End ─────────────────────────
                if (type == 'upcoming' 
                    && !appointments.isEmpty()) {
                    response += 
                        'What would you like to do?\n'
                        + '- Reschedule an appointment\n'
                        + '- Cancel an appointment\n'
                        + '- Book a new appointment';
                } else if (type == 'past'
                    && !appointments.isEmpty()) {
                    response +=
                        'Would you like to:\n'
                        + '- Book a new appointment\n'
                        + '- View upcoming appointments';
                }

                res.displayText = response;

            } catch(Exception e) {
                res.displayText =
                    'Unable to fetch appointments.\n'
                    + 'Please call 1800-ONCO-CARE.';
            }

            results.add(res);
        }
        return results;
    }
}