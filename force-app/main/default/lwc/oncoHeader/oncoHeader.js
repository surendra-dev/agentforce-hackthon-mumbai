import { LightningElement, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import basePath from '@salesforce/community/basePath';
import USER_ID from '@salesforce/user/Id';
import USER_NAME_FIELD from '@salesforce/schema/User.Name';
import HEADER_LOGO from '@salesforce/resourceUrl/oncoHeaderLogo';

export default class OncoHeader extends LightningElement {
    logoUrl = HEADER_LOGO;
    userName = 'User';

    @wire(getRecord, { recordId: USER_ID, fields: [USER_NAME_FIELD] })
    wiredUser({ data }) {
        if (data) {
            this.userName = getFieldValue(data, USER_NAME_FIELD) || 'User';
        }
    }

    handleLogoutClick() {
        const siteRoot = basePath.replace(/\/s$/i, '');
        window.location.assign(`${siteRoot}/secur/logout.jsp`);
    }
}