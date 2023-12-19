import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {StringComponent} from '@eg/share/string/string.component';
import {WorkLogService, WorkLogEntry} from './worklog.service';

/** Component for housing strings related to the worklog service
 *
 * NOTE: once we have in-code i18n support, this and our module
 * can go away, leaving only the service
 */


@Component({
    templateUrl: 'strings.component.html',
    selector: 'eg-worklog-strings-components'
})
export class WorkLogStringsComponent {

    // Worklog string variable names have to match "worklog_{{action}}"
    @ViewChild('worklog_checkout') worklog_checkout: StringComponent;
    @ViewChild('worklog_checkin') worklog_checkin: StringComponent;
    @ViewChild('worklog_noncat_checkout') worklog_noncat_checkout: StringComponent;
    @ViewChild('worklog_renew') worklog_renew: StringComponent;
    @ViewChild('worklog_requested_hold') worklog_requested_hold: StringComponent;
    @ViewChild('worklog_canceled_hold') worklog_canceled_hold: StringComponent;
    @ViewChild('worklog_edited_patron') worklog_edited_patron: StringComponent;
    @ViewChild('worklog_registered_patron') worklog_registered_patron: StringComponent;
    @ViewChild('worklog_paid_bill') worklog_paid_bill: StringComponent;

    constructor(private worklog: WorkLogService) {
        this.worklog.workLogStrings = this;
    }
}

