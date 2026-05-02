/* OncoAppointmentController
 * Read-only dashboard data for patient appointments.
 */
public without sharing class OncoAppointmentController {

    @AuraEnabled(cacheable=true)
    public static List<AppointmentWrapper> getMyAppointments() {
        Id contactId = getLoggedInContactId();
        if (contactId == null) {
            return new List<AppointmentWrapper>();
        }

        List<AppointmentWrapper> results = new List<AppointmentWrapper>();

        List<ServiceAppointment> appointments = [
            SELECT Id, AppointmentNumber, Subject, Description, Status,
                   SchedStartTime, SchedEndTime, EarliestStartTime,
                   ContactId, AccountId, ParentRecordId, ParentRecord.Name
            FROM ServiceAppointment
            WHERE ContactId = :contactId
            ORDER BY SchedStartTime DESC
            LIMIT 100
        ];

        Map<Id, String> appointmentDoctorNames = getAppointmentDoctorNames(appointments);

        for (ServiceAppointment sa : appointments) {
            AppointmentWrapper aw = new AppointmentWrapper();
            aw.id = sa.Id;
            aw.appointmentNumber = sa.AppointmentNumber;
            aw.subject = sa.Subject;
            aw.description = sa.Description;
            aw.status = sa.Status;
            aw.schedStartTime = sa.SchedStartTime;
            aw.schedEndTime = sa.SchedEndTime;
            aw.providerName = appointmentDoctorNames.containsKey(sa.Id)
                ? appointmentDoctorNames.get(sa.Id)
                : 'Unassigned';
            aw.facilityName = sa.ParentRecord != null ? sa.ParentRecord.Name : '';
            aw.isCanceled = isCanceledStatus(sa.Status);
            aw.isUpcoming = isUpcomingStatus(sa.Status);
            aw.isPast = isPastStatus(sa.Status);
            results.add(aw);
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardStats getDashboardStats() {
        Id contactId = getLoggedInContactId();
        DashboardStats stats = new DashboardStats();
        if (contactId == null) return stats;

        List<ServiceAppointment> allAppts = [
            SELECT Id, Status, SchedStartTime, EarliestStartTime
            FROM ServiceAppointment
            WHERE ContactId = :contactId
        ];

        Integer upcoming = 0;
        Integer canceled = 0;
        Integer thisMonth = 0;
        Date today = Date.today();
        Integer currentMonth = today.month();
        Integer currentYear = today.year();

        for (ServiceAppointment sa : allAppts) {
            if (!isTrackedAppointment(sa.Status)) {
                continue;
            }

            if (isCanceledStatus(sa.Status)) {
                canceled++;
            }
            if (isUpcomingStatus(sa.Status)) {
                upcoming++;
            }
            if (sa.SchedStartTime != null && sa.SchedStartTime.month() == currentMonth && sa.SchedStartTime.year() == currentYear) {
                thisMonth++;
            }
            stats.total++;
        }
        stats.upcoming = upcoming;
        stats.canceled = canceled;
        stats.thisMonth = thisMonth;
        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static DebugInfo getDebugInfo() {
        DebugInfo info = new DebugInfo();

        User u = [
            SELECT Id, ContactId, AccountId, Account.PersonContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        info.userId = u.Id;
        info.userContactId = u.ContactId;
        info.userAccountId = u.AccountId;
        info.personContactId = u.AccountId != null && u.Account != null
            ? u.Account.PersonContactId
            : null;
        info.resolvedContactId = getLoggedInContactId();

        if (info.resolvedContactId == null) {
            return info;
        }

        List<ServiceAppointment> matchingAppointments = [
            SELECT Id, AppointmentNumber, ContactId, Status,
                   SchedStartTime, EarliestStartTime
            FROM ServiceAppointment
            WHERE ContactId = :info.resolvedContactId
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];

        info.matchingAppointmentCount = matchingAppointments.size();
        for (ServiceAppointment sa : matchingAppointments) {
            info.appointments.add(
                sa.AppointmentNumber
                + ' | ContactId=' + sa.ContactId
                + ' | Status=' + sa.Status
                + ' | SchedStart=' + String.valueOf(sa.SchedStartTime)
                + ' | EarliestStart=' + String.valueOf(sa.EarliestStartTime)
            );
        }

        return info;
    }

    private static Id getLoggedInContactId() {
        User u = [
            SELECT ContactId, AccountId, Account.PersonContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (u.ContactId != null) {
            return u.ContactId;
        }

        if (u.AccountId != null && u.Account.PersonContactId != null) {
            return u.Account.PersonContactId;
        }

        return null;
    }

    private static Boolean isCanceledStatus(String status) {
        String normalizedStatus = normalizeStatus(status);
        return normalizedStatus == 'canceled' || normalizedStatus == 'cancelled';
    }

    private static Boolean isUpcomingStatus(String status) {
        String normalizedStatus = normalizeStatus(status);
        return normalizedStatus == 'scheduled' ||
            normalizedStatus == 'dispatched' ||
            normalizedStatus == 'in progress';
    }

    private static Boolean isPastStatus(String status) {
        String normalizedStatus = normalizeStatus(status);
        return normalizedStatus == 'completed' ||
            normalizedStatus == 'cannot complete' ||
            normalizedStatus == 'review';
    }

    private static Boolean isTrackedAppointment(String status) {
        String normalizedStatus = normalizeStatus(status);
        return !String.isBlank(normalizedStatus) && normalizedStatus != 'none';
    }

    private static String normalizeStatus(String status) {
        return String.isBlank(status) ? '' : status.trim().toLowerCase();
    }

    private static Map<Id, String> getAppointmentDoctorNames(List<ServiceAppointment> appointments) {
        Map<Id, String> appointmentDoctorNames = new Map<Id, String>();
        Set<Id> appointmentIds = new Set<Id>();

        for (ServiceAppointment appointment : appointments) {
            appointmentIds.add(appointment.Id);
        }

        if (appointmentIds.isEmpty()) {
            return appointmentDoctorNames;
        }

        for (AssignedResource assignment : [
            SELECT ServiceAppointmentId, ServiceResource.Name
            FROM AssignedResource
            WHERE ServiceAppointmentId IN :appointmentIds
            AND ServiceResource.Name != null
            ORDER BY LastModifiedDate DESC
        ]) {
            if (!appointmentDoctorNames.containsKey(assignment.ServiceAppointmentId)) {
                appointmentDoctorNames.put(
                    assignment.ServiceAppointmentId,
                    assignment.ServiceResource.Name
                );
            }
        }

        return appointmentDoctorNames;
    }

    // ---- Wrapper Classes ----

    public class AppointmentWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String appointmentNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime schedStartTime;
        @AuraEnabled public Datetime schedEndTime;
        @AuraEnabled public String providerName;
        @AuraEnabled public String providerSpecialty;
        @AuraEnabled public String facilityName;
        @AuraEnabled public Boolean isUpcoming;
        @AuraEnabled public Boolean isPast;
        @AuraEnabled public Boolean isCanceled;
    }

    public class DashboardStats {
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer upcoming = 0;
        @AuraEnabled public Integer canceled = 0;
        @AuraEnabled public Integer thisMonth = 0;
    }

    public class DebugInfo {
        @AuraEnabled public Id userId;
        @AuraEnabled public Id userContactId;
        @AuraEnabled public Id userAccountId;
        @AuraEnabled public Id personContactId;
        @AuraEnabled public Id resolvedContactId;
        @AuraEnabled public Integer matchingAppointmentCount = 0;
        @AuraEnabled public List<String> appointments = new List<String>();
    }
}