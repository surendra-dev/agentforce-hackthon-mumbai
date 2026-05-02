import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import HEADER_LOGO from '@salesforce/resourceUrl/oncoHeaderLogo';
import ONCOLOGY_PHOTO from '@salesforce/resourceUrl/oncoLoginBgg';

export default class OncoLandingPage extends NavigationMixin(LightningElement) {
    currentView = 'landing';
    oncologyPhotoUrl = ONCOLOGY_PHOTO;
    headerLogoUrl = HEADER_LOGO;

    features = [
        { id: '1', icon: 'utility:chat', title: 'AI Care Navigator', desc: 'Get instant answers about specialties, locations, and services through our intelligent assistant.' },
        { id: '2', icon: 'utility:event', title: 'Easy Scheduling', desc: 'Book, modify, or cancel appointments in seconds without waiting on hold.' },
        { id: '3', icon: 'standard:location', title: '10+ Hospitals', desc: 'Access our network of cancer care centers across all major Indian cities.' },
        { id: '4', icon: 'standard:people', title: 'Find Specialists', desc: 'Discover the right oncology specialist based on your needs and location.' },
        { id: '5', icon: 'utility:clock', title: 'Zero Wait Time', desc: 'Self-service portal eliminates phone queues. Get care navigation anytime.' },
        { id: '6', icon: 'utility:shield', title: 'Trusted Care', desc: 'State-of-the-art facilities with PET-CT, CyberKnife, and dedicated ICUs.' }
    ];

    specialties = [
        { id: 's1', name: 'Medical Oncology', desc: 'Chemotherapy & immunotherapy' },
        { id: 's2', name: 'Surgical Oncology', desc: 'Cancer surgery & procedures' },
        { id: 's3', name: 'Radiation Oncology', desc: 'Radiation therapy treatments' },
        { id: 's4', name: 'Pediatric Oncology', desc: 'Childhood cancer care' },
        { id: 's5', name: 'Gynecologic Oncology', desc: 'Women\'s cancer specialist' },
        { id: 's6', name: 'Hematology', desc: 'Blood cancer treatment' }
    ];

    get showPatientDashboard() {
        return this.currentView === 'patientDashboard';
    }

    get showHospitalList() {
        return this.currentView === 'hospitalList';
    }

    get showDoctorList() {
        return this.currentView === 'doctorList';
    }

    get showLandingContent() {
        return this.currentView === 'landing';
    }

    handleBookAppointment() {
        this.currentView = 'patientDashboard';
    }

    navigateToHospitals() {
        this.currentView = 'hospitalList';
    }

    navigateToDoctors() {
        this.currentView = 'doctorList';
    }

    navigateToHome() {
        this.currentView = 'landing';
    }

    handleSpecialtyClick(event) {
        const specialty = event.currentTarget.dataset.specialty;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Doctors__c'  // Update with your Experience Cloud page name
            },
            state: {
                specialty: specialty
            }
        });
    }
}