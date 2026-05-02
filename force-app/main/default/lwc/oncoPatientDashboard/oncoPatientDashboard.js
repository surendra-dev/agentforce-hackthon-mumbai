import { LightningElement, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getMyAppointments from '@salesforce/apex/OncoAppointmentController.getMyAppointments';
import getDashboardStats from '@salesforce/apex/OncoAppointmentController.getDashboardStats';
import USER_ID from '@salesforce/user/Id';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';

export default class OncoPatientDashboard extends LightningElement {

    @track appointments = [];
    @track stats = { total: 0, upcoming: 0, canceled: 0, thisMonth: 0 };
    selectedFilter = 'upcoming';
    isLoading = true;
    userName = 'Patient';

    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME_FIELD] })
    wiredUser({ data, error }) {
        if (data) {
            this.userName = getFieldValue(data, USER_NAME_FIELD) || 'Patient';
        } else if (error) {
            console.error('Error loading user name:', error);
        }
    }

    @wire(getMyAppointments)
    wiredAppointments({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.appointments = data.map(a => this.formatAppointment(a));
        } else if (error) {
            console.error('Error loading appointments:', error);
        }
    }

    @wire(getDashboardStats)
    wiredStats({ data, error }) {
        if (data) {
            this.stats = data;
        } else if (error) {
            console.error('Error loading stats:', error);
        }
    }

    formatAppointment(appt) {
        let formattedDate = '';
         let formattedTime = '';
        if (appt.schedStartTime) {
            const dt = new Date(appt.schedStartTime);
            const istOptions = { timeZone: 'Asia/Kolkata' };
            formattedDate = dt.toLocaleDateString('en-IN', {
                ...istOptions,
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
            formattedTime = dt.toLocaleTimeString('en-IN', {
                ...istOptions,
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        }

        const normalizedStatus = (appt.status || '').toLowerCase();
        const isCanceled = normalizedStatus === 'canceled' || normalizedStatus === 'cancelled';
        const isUpcoming = appt.isUpcoming === true;
        const isPast = appt.isPast === true;

        let statusBadgeClass = 'status-badge ';
        switch (normalizedStatus) {
            case 'scheduled':
            case 'dispatched':
            case 'in progress':
                statusBadgeClass += 'status-confirmed';
                break;
            case 'canceled':
            case 'cancelled':
                statusBadgeClass += 'status-canceled';
                break;
            case 'completed':
            case 'review':
                statusBadgeClass += 'status-completed';
                break;
            case 'cannot complete':
                statusBadgeClass += 'status-canceled';
                break;
            default:
                statusBadgeClass += 'status-pending';
        }

        return {
            ...appt,
            formattedDate,
            formattedTime,
            statusBadgeClass,
            isCanceled,
            isUpcoming,
            isPastOrCanceled: isCanceled || isPast
        };
    }

    get upcomingAppointments() {
        return this.appointments.filter(a => a.isUpcoming);
    }

    get canceledAppointments() {
        return this.appointments.filter(a => a.isCanceled);
    }

    get totalBookedAppointments() {
        return this.appointments;
    }

    get pastAppointments() {
        return this.appointments.filter(a => a.isPastOrCanceled);
    }

    get filteredAppointments() {
        switch (this.selectedFilter) {
            case 'total':
                return this.totalBookedAppointments;
            case 'canceled':
                return this.canceledAppointments;
            case 'upcoming':
                return this.upcomingAppointments;
            default:
                return this.upcomingAppointments;
        }
    }

    get hasSelectedFilter() {
        return !!this.selectedFilter;
    }

    get hasFilteredAppointments() {
        return this.hasSelectedFilter && this.filteredAppointments.length > 0;
    }

    get sectionHeading() {
        switch (this.selectedFilter) {
            case 'total':
                return 'All Booked Appointments';
            case 'canceled':
                return 'Cancelled Appointments';
            case 'upcoming':
            default:
                return 'Upcoming Appointments';
        }
    }

    get sectionSubheading() {
        switch (this.selectedFilter) {
            case 'total':
                return 'All appointments linked to your patient contact.';
            case 'canceled':
                return 'Appointments with cancelled or canceled status.';
            case 'upcoming':
            default:
                return 'Appointments with active status such as Scheduled, Dispatched, or In Progress.';
        }
    }

    get emptyTitle() {
        switch (this.selectedFilter) {
            case 'total':
                return 'No booked appointments';
            case 'canceled':
                return 'No cancelled appointments';
            case 'upcoming':
            default:
                return 'No upcoming appointments';
        }
    }

    get emptyText() {
        switch (this.selectedFilter) {
            case 'total':
                return 'Appointments linked to your patient profile will appear here once they are created.';
            case 'canceled':
                return 'Cancelled appointments will appear here when any booking is canceled.';
            case 'upcoming':
            default:
                return 'Your scheduled visits will appear here once they are created with an active appointment status.';
        }
    }

    get selectionPromptTitle() {
        return 'Select a dashboard block';
    }

    get selectionPromptText() {
        return 'Choose Upcoming, Total Booked, or Cancelled to view the matching appointments.';
    }

    get upcomingCardClass() {
        return this.getStatCardClass('upcoming');
    }

    get totalCardClass() {
        return this.getStatCardClass('total');
    }

    get canceledCardClass() {
        return this.getStatCardClass('canceled');
    }

    getStatCardClass(filterName) {
        return this.selectedFilter === filterName
            ? 'stat-card stat-card-active'
            : 'stat-card';
    }

    handleFilterSelect(event) {
        this.selectedFilter = event.currentTarget.dataset.filter;
    }

    handleBackHome() {
        this.dispatchEvent(new CustomEvent('home'));
    }
}