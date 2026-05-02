/* OncoFacilityController
 * Apex controller for Healthcare Facility queries
 * Used by: oncoHospitalList LWC
 *
 * Object: HealthcareFacility (Standard Health Cloud)
 * Related: Account (Master-Detail for address/phone)
 */
public without sharing class OncoFacilityController {

    /**
     * Get all healthcare facilities with related Account details
     */
    @AuraEnabled(cacheable=true)
    public static List<FacilityWrapper> getHealthcareFacilities() {
        List<FacilityWrapper> results = new List<FacilityWrapper>();

        List<HealthcareFacility> facilities = [
            SELECT Id, Name, LicensedBedCount, IsAlwaysOpen, LocationType,
                   AccountId, Account.Name, Account.Phone,
                   Account.BillingStreet, Account.BillingCity,
                   Account.BillingState, Account.BillingPostalCode,
                   Account.BillingCountry
            FROM HealthcareFacility
            ORDER BY Name ASC
            LIMIT 50
        ];

        for (HealthcareFacility f : facilities) {
            FacilityWrapper fw = new FacilityWrapper();
            fw.id = f.Id;
            fw.name = f.Name;
            fw.bedCount = f.LicensedBedCount != null ? Integer.valueOf(f.LicensedBedCount) : 0;
            fw.isAlwaysOpen = f.IsAlwaysOpen;
            fw.locationType = f.LocationType;
            fw.phone = f.Account != null ? f.Account.Phone : '';
            fw.city = f.Account != null ? f.Account.BillingCity : '';
            fw.state = f.Account != null ? f.Account.BillingState : '';
            fw.address = '';
            if (f.Account != null) {
                List<String> addrParts = new List<String>();
                if (String.isNotBlank(f.Account.BillingStreet)) addrParts.add(f.Account.BillingStreet);
                if (String.isNotBlank(f.Account.BillingCity)) addrParts.add(f.Account.BillingCity);
                if (String.isNotBlank(f.Account.BillingState)) addrParts.add(f.Account.BillingState);
                if (String.isNotBlank(f.Account.BillingPostalCode)) addrParts.add(f.Account.BillingPostalCode);
                fw.address = String.join(addrParts, ', ');
            }
            results.add(fw);
        }
        return results;
    }

    /**
     * Search facilities by name or city
     */
    @AuraEnabled(cacheable=true)
    public static List<FacilityWrapper> searchFacilities(String searchTerm) {
        String searchKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<FacilityWrapper> results = new List<FacilityWrapper>();

        List<HealthcareFacility> facilities = [
            SELECT Id, Name, LicensedBedCount, IsAlwaysOpen, LocationType,
                   AccountId, Account.Name, Account.Phone,
                   Account.BillingStreet, Account.BillingCity,
                   Account.BillingState, Account.BillingPostalCode
            FROM HealthcareFacility
            WHERE Name LIKE :searchKey
               OR Account.BillingCity LIKE :searchKey
               OR Account.BillingState LIKE :searchKey
            ORDER BY Name ASC
            LIMIT 50
        ];

        for (HealthcareFacility f : facilities) {
            FacilityWrapper fw = new FacilityWrapper();
            fw.id = f.Id;
            fw.name = f.Name;
            fw.bedCount = f.LicensedBedCount != null ? Integer.valueOf(f.LicensedBedCount) : 0;
            fw.isAlwaysOpen = f.IsAlwaysOpen;
            fw.locationType = f.LocationType;
            fw.phone = f.Account != null ? f.Account.Phone : '';
            fw.city = f.Account != null ? f.Account.BillingCity : '';
            fw.state = f.Account != null ? f.Account.BillingState : '';
            fw.address = '';
            if (f.Account != null) {
                List<String> addrParts = new List<String>();
                if (String.isNotBlank(f.Account.BillingStreet)) addrParts.add(f.Account.BillingStreet);
                if (String.isNotBlank(f.Account.BillingCity)) addrParts.add(f.Account.BillingCity);
                if (String.isNotBlank(f.Account.BillingState)) addrParts.add(f.Account.BillingState);
                fw.address = String.join(addrParts, ', ');
            }
            results.add(fw);
        }
        return results;
    }

    /**
     * Get single facility by Id
     */
    @AuraEnabled(cacheable=true)
    public static FacilityWrapper getFacilityById(Id facilityId) {
        HealthcareFacility f = [
            SELECT Id, Name, LicensedBedCount, IsAlwaysOpen, LocationType,
                   AccountId, Account.Name, Account.Phone,
                   Account.BillingStreet, Account.BillingCity,
                   Account.BillingState, Account.BillingPostalCode
            FROM HealthcareFacility
            WHERE Id = :facilityId
            LIMIT 1
        ];

        FacilityWrapper fw = new FacilityWrapper();
        fw.id = f.Id;
        fw.name = f.Name;
        fw.bedCount = f.LicensedBedCount != null ? Integer.valueOf(f.LicensedBedCount) : 0;
        fw.isAlwaysOpen = f.IsAlwaysOpen;
        fw.locationType = f.LocationType;
        fw.phone = f.Account != null ? f.Account.Phone : '';
        fw.city = f.Account != null ? f.Account.BillingCity : '';
        fw.state = f.Account != null ? f.Account.BillingState : '';
        fw.address = '';
        if (f.Account != null) {
            List<String> addrParts = new List<String>();
            if (String.isNotBlank(f.Account.BillingStreet)) addrParts.add(f.Account.BillingStreet);
            if (String.isNotBlank(f.Account.BillingCity)) addrParts.add(f.Account.BillingCity);
            if (String.isNotBlank(f.Account.BillingState)) addrParts.add(f.Account.BillingState);
            fw.address = String.join(addrParts, ', ');
        }
        return fw;
    }

    /**
     * Wrapper class for clean data transfer to LWC
     */
    public class FacilityWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer bedCount;
        @AuraEnabled public Boolean isAlwaysOpen;
        @AuraEnabled public String locationType;
        @AuraEnabled public String phone;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String address;
    }
}