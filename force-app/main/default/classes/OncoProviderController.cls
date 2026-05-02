/* OncoProviderController
 * Apex controller for Healthcare Provider queries
 * Used by: oncoDoctorList LWC
 *
 * Object: HealthcareProvider (Standard Health Cloud)
 * Junction: HealthcarePractitionerFacility (links Provider to Facility)
 *
 * NO CUSTOM FIELDS - Uses only standard fields:
 *   - Name, ProfessionalTitle, ProviderClass, ProviderType
 *   - PractitionerId (Contact), ProviderPhotoId, EffectiveFrom, Status, AccountId
 */
public without sharing class OncoProviderController {

    /**
     * Get all active healthcare providers with Contact and Facility details
     */
    @AuraEnabled(cacheable=true)
    public static List<ProviderWrapper> getProviders() {
        List<ProviderWrapper> results = new List<ProviderWrapper>();

        List<HealthcareProvider> providers = [
            SELECT Id, Name, IsActive, ProfessionalTitle, ProviderClass,
                   ProviderType, Status, EffectiveFrom, ProviderPhotoId,
                   AccountId, Account.Name,
                   PractitionerId, Practitioner.Name,
                   Practitioner.Email, Practitioner.Phone
            FROM HealthcareProvider
            WHERE IsActive = true
            ORDER BY Name ASC
            LIMIT 200
        ];

        // Get facility mappings via junction object
        Set<Id> providerIds = new Set<Id>();
        for (HealthcareProvider p : providers) {
            providerIds.add(p.Id);
        }

        Map<Id, HealthcarePractitionerFacility> provFacilityMap = new Map<Id, HealthcarePractitionerFacility>();
        if (!providerIds.isEmpty()) {
            for (HealthcarePractitionerFacility pf : [
                SELECT Id, HealthcareProviderId, HealthcareFacilityId,
                       HealthcareFacility.Name,
                       HealthcareFacility.AccountId,
                       HealthcareFacility.Account.BillingCity
                FROM HealthcarePractitionerFacility
                WHERE HealthcareProviderId IN :providerIds
            ]) {
                provFacilityMap.put(pf.HealthcareProviderId, pf);
            }
        }

        for (HealthcareProvider p : providers) {
            ProviderWrapper pw = new ProviderWrapper();
            pw.id = p.Id;
            pw.name = p.Name;
            pw.professionalTitle = p.ProfessionalTitle != null ? p.ProfessionalTitle : '';
            pw.providerClass = p.ProviderClass != null ? p.ProviderClass : '';
            pw.providerType = p.ProviderType != null ? p.ProviderType : '';
            pw.status = p.Status;

            // Calculate experience from EffectiveFrom
            if (p.EffectiveFrom != null) {
                Integer years = p.EffectiveFrom.daysBetween(Date.today()) / 365;
                pw.experienceYears = years > 0 ? years : 0;
            } else {
                pw.experienceYears = 0;
            }

            // Contact details via PractitionerId
            pw.contactName = (p.Practitioner != null) ? p.Practitioner.Name : p.Name;
            pw.contactEmail = (p.Practitioner != null) ? p.Practitioner.Email : '';
            pw.contactPhone = (p.Practitioner != null) ? p.Practitioner.Phone : '';

            // Photo
            pw.hasPhoto = (p.ProviderPhotoId != null);
            pw.photoUrl = p.ProviderPhotoId != null
                ? '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB120BY90&versionId=' + p.ProviderPhotoId
                : '';

            // Facility info from junction
            if (provFacilityMap.containsKey(p.Id)) {
                HealthcarePractitionerFacility pf = provFacilityMap.get(p.Id);
                pw.facilityId = pf.HealthcareFacilityId;
                pw.facilityName = pf.HealthcareFacility != null ? pf.HealthcareFacility.Name : '';
                pw.facilityAccountId = pf.HealthcareFacility != null ? pf.HealthcareFacility.AccountId : null;
                pw.facilityCity = (pf.HealthcareFacility != null && pf.HealthcareFacility.Account != null)
                    ? pf.HealthcareFacility.Account.BillingCity : '';
            }

            results.add(pw);
        }
        return results;
    }

	@AuraEnabled(cacheable=true)
    public static List<ProviderWrapper> getProvidersByFacility(Id facilityId) {
    
        List<ProviderWrapper> results = new List<ProviderWrapper>();
    
        List<HealthcarePractitionerFacility> junctions = [
            SELECT Id,PractitionerId,
                   HealthcareFacilityId,HealthcareFacility.Name,HealthcareFacility.AccountId,HealthcareFacility.Account.BillingCity,
				   Practitioner.Name,Practitioner.Email,Practitioner.Phone,HealthcareProvider.Id,HealthcareProvider.Name,
                   HealthcareProvider.IsActive,HealthcareProvider.ProfessionalTitle,HealthcareProvider.ProviderClass,HealthcareProvider.ProviderType,
                   HealthcareProvider.EffectiveFrom,HealthcareProvider.Status,HealthcareProvider.ProviderPhotoId
    		FROM HealthcarePractitionerFacility
            WHERE HealthcareFacilityId = :facilityId
            AND HealthcareProvider.IsActive = true
            ORDER BY HealthcareProvider.Name ASC
        ];
    
        for (HealthcarePractitionerFacility pf : junctions) {
            HealthcareProvider hp = pf.HealthcareProvider;
            ProviderWrapper pw = new ProviderWrapper();
            pw.id = hp.Id;
            pw.name = hp.Name;
            pw.professionalTitle = hp.ProfessionalTitle != null ? hp.ProfessionalTitle : '';
            pw.providerClass = hp.ProviderClass != null ? hp.ProviderClass : '';
            pw.providerType = hp.ProviderType != null ? hp.ProviderType : '';
            pw.status = hp.Status;
    
            if (hp.EffectiveFrom != null) {
                pw.experienceYears =
                    hp.EffectiveFrom.daysBetween(Date.today()) / 365;
            } else {
                pw.experienceYears = 0;
            }
    
            pw.contactName =
                pf.Practitioner != null ? pf.Practitioner.Name : hp.Name;
    
            pw.contactEmail =
                pf.Practitioner != null ? pf.Practitioner.Email : '';
    
            pw.contactPhone =
                pf.Practitioner != null ? pf.Practitioner.Phone : '';
    
            pw.hasPhoto = hp.ProviderPhotoId != null;
    
            pw.facilityId = pf.HealthcareFacilityId;
    
            pw.facilityName =
                pf.HealthcareFacility != null
                ? pf.HealthcareFacility.Name
                : '';
    
            pw.facilityAccountId =
                pf.HealthcareFacility != null
                ? pf.HealthcareFacility.AccountId
                : null;
    
            pw.facilityCity =
                (pf.HealthcareFacility != null &&
                 pf.HealthcareFacility.Account != null)
                ? pf.HealthcareFacility.Account.BillingCity
                : '';
    
            results.add(pw);
        }
    
        return results;
    }



    /**
     * Get distinct professional titles for filter dropdown
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getSpecialties() {
        Set<String> titleSet = new Set<String>();
        for (HealthcareProvider p : [
            SELECT ProfessionalTitle
            FROM HealthcareProvider
            WHERE IsActive = true AND ProfessionalTitle != null
        ]) {
            titleSet.add(p.ProfessionalTitle);
        }
        List<String> titles = new List<String>(titleSet);
        titles.sort();
        return titles;
    }

    /**
     * Wrapper class — NO custom fields used
     */
    public class ProviderWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String professionalTitle;   // ProfessionalTitle picklist
        @AuraEnabled public String providerClass;       // ProviderClass picklist
        @AuraEnabled public String providerType;        // ProviderType picklist
        @AuraEnabled public String status;
        @AuraEnabled public Integer experienceYears;    // Calculated from EffectiveFrom
        @AuraEnabled public String contactName;         // From Practitioner (Contact)
        @AuraEnabled public String contactEmail;        // From Practitioner (Contact)
        @AuraEnabled public String contactPhone;        // From Practitioner (Contact)
        @AuraEnabled public Boolean hasPhoto;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public Id facilityId;
        @AuraEnabled public String facilityName;
        @AuraEnabled public Id facilityAccountId;       // Account linked to Facility
        @AuraEnabled public String facilityCity;
    }
}