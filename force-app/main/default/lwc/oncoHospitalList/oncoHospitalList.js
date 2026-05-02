import { LightningElement, wire } from 'lwc';
import getHealthcareFacilities from '@salesforce/apex/OncoFacilityController.getHealthcareFacilities';

export default class OncoHospitalList extends LightningElement {
    facilities = [];
    searchTerm = '';
    selectedFacilityId = '';
    selectedFacilityName = '';
    isLoading = true;

    @wire(getHealthcareFacilities)
    wiredFacilities({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.facilities = data;
        } else if (error) {
            console.error('Error loading facilities:', error);
            this.facilities = [];
        }
    }

    get filteredFacilities() {
        if (!this.searchTerm) {
            return this.facilities;
        }

        const term = this.searchTerm.toLowerCase();
        return this.facilities.filter(hospital =>
            (hospital.name && hospital.name.toLowerCase().includes(term)) ||
            (hospital.city && hospital.city.toLowerCase().includes(term)) ||
            (hospital.state && hospital.state.toLowerCase().includes(term))
        );
    }

    get resultCount() {
        return this.filteredFacilities.length;
    }

    get isEmpty() {
        return !this.isLoading && this.filteredFacilities.length === 0;
    }

    get showHospitalDirectory() {
        return !this.selectedFacilityId;
    }

    get showDoctorDirectory() {
        return !!this.selectedFacilityId;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleViewDoctors(event) {
        this.selectedFacilityId = event.currentTarget.dataset.id;
        this.selectedFacilityName = event.currentTarget.dataset.name || '';
    }

    handleBackToHospitals() {
        this.selectedFacilityId = '';
        this.selectedFacilityName = '';
    }

    handleBackHome() {
        this.dispatchEvent(new CustomEvent('home'));
    }
}