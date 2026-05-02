import { LightningElement, wire, track, api } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getProviders from '@salesforce/apex/OncoProviderController.getProviders';
import getProvidersByFacility from '@salesforce/apex/OncoProviderController.getProvidersByFacility';
import getSpecialties from '@salesforce/apex/OncoProviderController.getSpecialties';
import getHealthcareFacilities from '@salesforce/apex/OncoFacilityController.getHealthcareFacilities';

export default class OncoDoctorList extends NavigationMixin(LightningElement) {
    @api initialFacilityId = '';
    @api initialFacilityName = '';

    @track doctors = [];
    @track facilities = [];
    @track specialties = [];
    @track searchTerm = '';
    @track selectedFacility = '';
    @track selectedSpecialty = '';
    isLoading = true;
    scopedFacilityId = '';

    connectedCallback() {
        if (this.initialFacilityId) {
            this.selectedFacility = this.initialFacilityId;
            this.scopedFacilityId = this.initialFacilityId;
        }
        this.loadDoctors();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (pageRef && pageRef.state) {
            if (pageRef.state.facilityId) {
                const shouldReload = !this.initialFacilityId && this.scopedFacilityId !== pageRef.state.facilityId;
                this.selectedFacility = pageRef.state.facilityId;
                if (!this.initialFacilityId) {
                    this.scopedFacilityId = pageRef.state.facilityId;
                }
                if (shouldReload) {
                    this.loadDoctors();
                }
            }
            if (pageRef.state.specialty) {
                this.selectedSpecialty = pageRef.state.specialty;
            }
        }
    }

    @wire(getSpecialties)
    wiredSpecialties({ error, data }) {
        if (data) {
            this.specialties = data;
        } else if (error) {
            console.error('Error loading specialties:', error);
        }
    }

    @wire(getHealthcareFacilities)
    wiredFacilities({ error, data }) {
        if (data) {
            this.facilities = data;
        } else if (error) {
            console.error('Error loading facilities:', error);
        }
    }

    normalizeDoctor(provider) {
        const specialty = provider.professionalTitle || provider.providerType || provider.providerClass || 'Oncology Specialist';
        return {
            ...provider,
            specialty,
            subtitle: provider.providerType || provider.providerClass || 'Healthcare Provider',
            qualification: provider.providerClass || provider.providerType || '',
            phone: provider.contactPhone || '',
            email: provider.contactEmail || ''
        };
    }

    loadDoctors() {
        this.isLoading = true;
        const providerRequest = this.isFacilityScoped
            ? getProvidersByFacility({ facilityId: this.selectedFacility })
            : getProviders();

        providerRequest
            .then(data => {
                this.doctors = data.map(provider => this.normalizeDoctor(provider));
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading providers:', error);
                this.doctors = [];
                this.isLoading = false;
            });
    }

    get facilityOptions() {
        const opts = [{ label: 'All Hospitals', value: '' }];
        this.facilities.forEach(facility => {
            opts.push({ label: facility.name, value: facility.id });
        });
        return opts;
    }

    get specialtyOptions() {
        const opts = [{ label: 'All Specialties', value: '' }];
        this.specialties.forEach(specialty => {
            opts.push({ label: specialty, value: specialty });
        });
        return opts;
    }

    get pageTitle() {
        return this.isFacilityScoped && this.resolvedFacilityName
            ? `Doctors at ${this.resolvedFacilityName}`
            : 'Find a Specialist';
    }

    get pageSubtitle() {
        return this.isFacilityScoped && this.resolvedFacilityName
            ? `Showing providers currently mapped to ${this.resolvedFacilityName}.`
            : 'Browse our network of oncology specialists by hospital, title, and experience.';
    }

    get resolvedFacilityName() {
        if (this.initialFacilityName) {
            return this.initialFacilityName;
        }

        const facility = this.facilities.find(item => item.id === this.selectedFacility);
        return facility ? facility.name : '';
    }

    get isFacilityScoped() {
        return !!this.scopedFacilityId;
    }

    get showFacilityFilter() {
        return !this.isFacilityScoped;
    }

    get filteredDoctors() {
        return this.doctors.filter(doctor => {
            const matchSearch = !this.searchTerm ||
                (doctor.name && doctor.name.toLowerCase().includes(this.searchTerm.toLowerCase())) ||
                (doctor.specialty && doctor.specialty.toLowerCase().includes(this.searchTerm.toLowerCase()));
            const matchFacility = !this.selectedFacility || doctor.facilityId === this.selectedFacility;
            const matchSpecialty = !this.selectedSpecialty || doctor.specialty === this.selectedSpecialty;
            return matchSearch && matchFacility && matchSpecialty;
        });
    }

    get resultCount() {
        return this.filteredDoctors.length;
    }

    get isEmpty() {
        return !this.isLoading && this.filteredDoctors.length === 0;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleFacilityChange(event) {
        this.selectedFacility = event.detail.value;
    }

    handleSpecialtyChange(event) {
        this.selectedSpecialty = event.detail.value;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleBackHome() {
        this.dispatchEvent(new CustomEvent('home'));
    }

    // handleBookDoctor(event) {
    //     const doctorId = event.currentTarget.dataset.doctorId;
    //     const facilityId = event.currentTarget.dataset.facilityId;
    //     this[NavigationMixin.Navigate]({
    //         type: 'comm__namedPage',
    //         attributes: {
    //             name: 'Book_Appointment__c'
    //         },
    //         state: {
    //             doctorId,
    //             facilityId
    //         }
    //     });
    // }
}