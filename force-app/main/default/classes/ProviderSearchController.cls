public without sharing class ProviderSearchController {

    public class Request {
        @InvocableVariable(required=false)
        public String locationName;

        @InvocableVariable(required=false)
        public String specialtyName;
    }

    public class Response {
        @InvocableVariable
        public String displayText;
    }

    @InvocableMethod(label='Find Providers' 
                     description='Find healthcare providers based on specialty and/or location')
    public static List<Response> findProviders(
        List<Request> requests) {

        List<Response> finalResults = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();
            
            String locationName = String.isBlank(req.locationName) 
                ? '' : req.locationName.trim();
            String specialtyName = String.isBlank(req.specialtyName) 
                ? '' : req.specialtyName.trim();

            if (String.isBlank(locationName) 
                && String.isBlank(specialtyName)) {
                res.displayText = 
                    'Please provide a city name or specialty '
                    + 'to search for providers.';
                finalResults.add(res);
                continue;
            }

            // ── Step 1: Find Accounts by city/name ───────
            Set<Id> accountIds = new Set<Id>();
            if (!String.isBlank(locationName)) {
                String locationSearch = '%' + locationName + '%';
                List<Account> matchedAccounts = [
                    SELECT Id FROM Account
                    WHERE BillingCity LIKE :locationSearch
                    OR BillingState LIKE :locationSearch
                    OR Name LIKE :locationSearch
                    LIMIT 20
                ];
                for (Account acc : matchedAccounts) {
                    accountIds.add(acc.Id);
                }
                if (accountIds.isEmpty()) {
                    res.displayText = 
                        'No facilities found in ' + locationName 
                        + '. Please try Mumbai, Delhi, '
                        + 'Bangalore or Chennai.';
                    finalResults.add(res);
                    continue;
                }
            }

            // ── Step 2: Get Healthcare Facilities ─────────
            List<HealthcareFacility> facilities = 
                String.isBlank(locationName)
                    ? [SELECT Id, Name 
                       FROM HealthcareFacility 
                       LIMIT 50]
                    : [SELECT Id, Name 
                       FROM HealthcareFacility 
                       WHERE AccountId IN :accountIds 
                       LIMIT 50];

            if (facilities.isEmpty()) {
                res.displayText = 
                    'No facilities found for your search. '
                    + 'Please try a different location.';
                finalResults.add(res);
                continue;
            }

            Set<Id> facilityIds = new Set<Id>();
            Map<Id, String> facilityMap = new Map<Id, String>();
            for (HealthcareFacility f : facilities) {
                facilityIds.add(f.Id);
                facilityMap.put(f.Id, f.Name);
            }

            // ── Step 3: Practitioner-Facility Mapping ─────
            List<HealthcarePractitionerFacility> practitionerFacilities = [
                SELECT HealthcareProviderId, HealthcareFacilityId
                FROM HealthcarePractitionerFacility
                WHERE HealthcareFacilityId IN :facilityIds
                AND isActive = TRUE
                LIMIT 200
            ];

            if (practitionerFacilities.isEmpty()) {
                res.displayText = 
                    'No providers are currently listed '
                    + 'at facilities in your area.';
                finalResults.add(res);
                continue;
            }

            Set<Id> allProviderIds = new Set<Id>();
            for (HealthcarePractitionerFacility pf : 
                practitionerFacilities) {
                allProviderIds.add(pf.HealthcareProviderId);
            }

            // ── Step 4: Specialty Filter ──────────────────
            Set<Id> filteredProviderIds = new Set<Id>();
            if (String.isBlank(specialtyName)) {
                filteredProviderIds = allProviderIds;
            } else {
                String specialtySearch = '%' + specialtyName + '%';
                List<HealthcareProviderSpecialty> specialties = [
                    SELECT PractitionerId, Name, Specialty.Name
                    FROM HealthcareProviderSpecialty
                    WHERE (Name LIKE :specialtySearch 
                    OR Specialty.Name LIKE :specialtySearch)
                    LIMIT 200
                ];
                Set<Id> practitionerIdsFromSpecialty = 
                    new Set<Id>();
                for (HealthcareProviderSpecialty sp : specialties) {
                    practitionerIdsFromSpecialty.add(
                        sp.PractitionerId);
                }
                List<HealthcareProvider> matchedProviders = [
                    SELECT Id FROM HealthcareProvider
                    WHERE PractitionerId 
                        IN :practitionerIdsFromSpecialty
                    AND Id IN :allProviderIds
                ];
                for (HealthcareProvider hp : matchedProviders) {
                    filteredProviderIds.add(hp.Id);
                }
                if (filteredProviderIds.isEmpty()) {
                    res.displayText = 
                        'No ' + specialtyName 
                        + ' specialists found in your area.\n'
                        + 'Please call 1800-ONCO-CARE '
                        + 'for assistance.';
                    finalResults.add(res);
                    continue;
                }
            }

            // ── Step 5: Get Provider Details ──────────────
            Map<Id, HealthcareProvider> providerMap = 
                new Map<Id, HealthcareProvider>(
                    [SELECT Id, Name,
                            PractitionerId,
                            InitialStartDate,
                            ProviderType
                     FROM HealthcareProvider 
                     WHERE Id IN :filteredProviderIds]
                );

            // ── Step 6: Get Primary Specialties ───────────
            List<HealthcareProviderSpecialty> providerSpecialties = [
                SELECT PractitionerId, Name, Specialty.Name
                FROM HealthcareProviderSpecialty
                WHERE PractitionerId IN (
                    SELECT PractitionerId
                    FROM HealthcareProvider
                    WHERE Id IN :filteredProviderIds
                )
                AND isActive = TRUE
                AND isPrimarySpecialty = TRUE
                LIMIT 200
            ];

            Map<Id, String> practitionerSpecialtyMap = 
                new Map<Id, String>();
            for (HealthcareProviderSpecialty sp : 
                providerSpecialties) {
                String specName = sp.Specialty != null
                    ? sp.Specialty.Name : sp.Name;
                practitionerSpecialtyMap.put(
                    sp.PractitionerId, specName);
            }

            // ── Step 7: Get Practitioner Contact Details ──
            List<HealthcareProvider> providersWithContact = [
                SELECT Id, PractitionerId,
                       Practitioner.Phone,
                       Practitioner.Email,
                       Practitioner.Title,
                       Practitioner.FirstName,
                       Practitioner.LastName
                FROM HealthcareProvider
                WHERE Id IN :filteredProviderIds
            ];

            // Map specialty and contact by Provider Id
            Map<Id, String> providerSpecialtyMap = 
                new Map<Id, String>();
            Map<Id, HealthcareProvider> providerContactMap = 
                new Map<Id, HealthcareProvider>();

            for (HealthcareProvider hp : providersWithContact) {
                providerContactMap.put(hp.Id, hp);
                if (practitionerSpecialtyMap
                    .containsKey(hp.PractitionerId)) {
                    providerSpecialtyMap.put(
                        hp.Id,
                        practitionerSpecialtyMap
                            .get(hp.PractitionerId));
                }
            }

            // ── Step 8: Build Enhanced Response ──────────
            List<String> providerLines = new List<String>();
            Set<String> seen = new Set<String>();
            Integer count = 1;

            for (HealthcarePractitionerFacility pf : 
                practitionerFacilities) {
                
                if (!filteredProviderIds.contains(
                        pf.HealthcareProviderId)
                    || !providerMap.containsKey(
                        pf.HealthcareProviderId)
                    || !facilityMap.containsKey(
                        pf.HealthcareFacilityId)) {
                    continue;
                }

                HealthcareProvider hp = providerMap
                    .get(pf.HealthcareProviderId);
                HealthcareProvider hpContact = 
                    providerContactMap.containsKey(
                        pf.HealthcareProviderId)
                    ? providerContactMap
                        .get(pf.HealthcareProviderId)
                    : null;

                String providerName = hp.Name;
                String facilityName = facilityMap
                    .get(pf.HealthcareFacilityId);
                String specialty = providerSpecialtyMap
                    .containsKey(pf.HealthcareProviderId)
                    ? providerSpecialtyMap
                        .get(pf.HealthcareProviderId)
                    : 'Oncology Specialist';

                // Get title/role
                String title = (hpContact != null
                    && hpContact.Practitioner != null
                    && !String.isBlank(
                        hpContact.Practitioner.Title))
                    ? hpContact.Practitioner.Title
                    : specialty;

                // Get phone
                String phone = (hpContact != null
                    && hpContact.Practitioner != null
                    && !String.isBlank(
                        hpContact.Practitioner.Phone))
                    ? hpContact.Practitioner.Phone
                    : 'Contact hospital';

                // Get email
                String email = (hpContact != null
                    && hpContact.Practitioner != null
                    && !String.isBlank(
                        hpContact.Practitioner.Email))
                    ? hpContact.Practitioner.Email
                    : 'Available on request';

                // Calculate experience
                String experience = '';
                if (hp.InitialStartDate != null) {
                    Integer years = hp.InitialStartDate
                        .daysBetween(Date.today()) / 365;
                    if (years > 0) {
                        experience = years 
                            + '+ years of experience';
                    }
                }

                String uniqueKey = providerName + facilityName;
                if (!seen.contains(uniqueKey)) {
                    seen.add(uniqueKey);
                    String line = 
                        count + '. ' + providerName + '\n'
                        + '   Specialty  : ' + specialty + '\n'
                        + '   Role       : ' + title + '\n'
                        + (!String.isBlank(experience)
                            ? '   Experience : ' 
                                + experience + '\n' : '')
                        + '   Hospital   : ' 
                            + facilityName + '\n'
                        + '   Phone      : ' + phone + '\n'
                        + '   Email      : ' + email;
                    providerLines.add(line);
                    count++;
                }
            }

            res.displayText = providerLines.isEmpty()
                ? 'No matching providers found.\n'
                    + 'Please call 1800-ONCO-CARE.'
                : 'Here are the available providers:\n\n'
                    + String.join(providerLines, '\n\n')
                    + '\n\nTo book an appointment, just say '
                    + '"Book with [Doctor Name]"!';

            finalResults.add(res);
        }

        return finalResults;
    }
}