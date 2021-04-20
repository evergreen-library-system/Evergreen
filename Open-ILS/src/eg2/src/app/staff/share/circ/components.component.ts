import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {CircService} from './circ.service';
import {PrecatCheckoutDialogComponent} from './precat-dialog.component';
import {CircEventsComponent} from './events-dialog.component';
import {StringComponent} from '@eg/share/string/string.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {OpenCircDialogComponent} from './open-circ-dialog.component';
import {RouteDialogComponent} from './route-dialog.component';
import {CopyInTransitDialogComponent} from './in-transit-dialog.component';
import {CopyAlertManagerDialogComponent
    } from '@eg/staff/share/holdings/copy-alert-manager.component';
import {WorkLogService, WorkLogEntry} from './work-log.service';

/* Container component for sub-components used by circulation actions.
 *
 * The CircService has to launch various dialogs for processing checkouts,
 * checkins, etc.  The service itself cannot contain components directly,
 * so we compile them here and provide references.
 * */

@Component({
  templateUrl: 'components.component.html',
  selector: 'eg-circ-components'
})
export class CircComponentsComponent {

    @ViewChild('precatDialog') precatDialog: PrecatCheckoutDialogComponent;
    @ViewChild('circEventsDialog') circEventsDialog: CircEventsComponent;
    @ViewChild('routeToCatalogingDialog') routeToCatalogingDialog: AlertDialogComponent;
    @ViewChild('openCircDialog') openCircDialog: OpenCircDialogComponent;
    @ViewChild('locationAlertDialog') locationAlertDialog: AlertDialogComponent;
    @ViewChild('uncatAlertDialog') uncatAlertDialog: AlertDialogComponent;
    @ViewChild('circFailedDialog') circFailedDialog: AlertDialogComponent;
    @ViewChild('routeDialog') routeDialog: RouteDialogComponent;
    @ViewChild('copyInTransitDialog') copyInTransitDialog: CopyInTransitDialogComponent;
    @ViewChild('copyAlertManager') copyAlertManager: CopyAlertManagerDialogComponent;

    @ViewChild('holdShelfStr') holdShelfStr: StringComponent;
    @ViewChild('catalogingStr') catalogingStr: StringComponent;

    // Worklog string variable names have to match "worklog_{{action}}"
    @ViewChild('worklog_checkout') worklog_checkout: StringComponent;
    @ViewChild('worklog_checkin') worklog_checkin: StringComponent;
    @ViewChild('worklog_noncat_checkout') worklog_noncat_checkout: StringComponent;
    @ViewChild('worklog_renew') worklog_renew: StringComponent;
    @ViewChild('worklog_requested_hold') worklog_requested_hold: StringComponent;
    @ViewChild('worklog_edited_patron') worklog_edited_patron: StringComponent;
    @ViewChild('worklog_registered_patron') worklog_registered_patron: StringComponent;
    @ViewChild('worklog_paid_bill') worklog_paid_bill: StringComponent;

    constructor(
        private worklog: WorkLogService,
        private circ: CircService) {
        this.circ.components = this;
        this.worklog.components = this;
    }
}

