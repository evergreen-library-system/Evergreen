import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, throwError, from} from 'rxjs';
import {switchMap} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {StringComponent} from '@eg/share/string/string.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/**
 * Dialog for managing copy alerts.
 */

export interface CopyAlertsChanges {
    newAlerts: IdlObject[];
    changedAlerts: IdlObject[];
}

@Component({
  selector: 'eg-copy-alerts-dialog',
  templateUrl: 'copy-alerts-dialog.component.html'
})

export class CopyAlertsDialogComponent
    extends DialogComponent implements OnInit {

    // If there are multiple copyIds, only new alerts may be applied.
    // If there is only one copyId, then alerts may be applied or removed.
    @Input() copyIds: number[] = [];

    mode: string; // create | manage

    // If true, no attempt is made to save new alerts to the
    // database.  It's assumed this takes place in the calling code.
    @Input() inPlaceCreateMode = false;

    // In 'create' mode, we may be adding notes to multiple copies.
    copies: IdlObject[];
    // In 'manage' mode we only handle a single copy.
    copy: IdlObject;

    alertTypes: ComboboxEntry[];
    newAlert: IdlObject;
    newAlerts: IdlObject[];
    autoId = -1;
    changesMade: boolean;

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService) {
        super(modal); // required for subclassing
        this.copyIds = [];
        this.copies = [];
    }

    ngOnInit() {}

    /**
     * Fetch the item/record, then open the dialog.
     * Dialog promise resolves with true/false indicating whether
     * the mark-damanged action occured or was dismissed.
     */
    open(args: NgbModalOptions): Observable<CopyAlertsChanges> {
        this.copy = null;
        this.copies = [];
        this.newAlert = this.idl.create('aca');
        this.newAlerts = [];
        this.newAlert.create_staff(this.auth.user().id());

        if (this.copyIds.length === 0 && !this.inPlaceCreateMode) {
            return throwError('copy ID required');
        }

        // In manage mode, we can only manage a single copy.
        // But in create mode, we can add alerts to multiple copies.
        // We can only manage copies that already exist in the database.
        if (this.copyIds.length === 1 && this.copyIds[0] > 0) {
            this.mode = 'manage';
        } else {
            this.mode = 'create';
        }

        // Observerify data loading
        const obs = from(
            this.getAlertTypes()
            .then(_ => this.getCopies())
            .then(_ => this.mode === 'manage' ? this.getCopyAlerts() : null)
        );

        // Return open() observable to caller
        return obs.pipe(switchMap(_ => super.open(args)));
    }

    getAlertTypes(): Promise<any> {
        if (this.alertTypes) { return Promise.resolve(); }

        return this.pcrud.retrieveAll('ccat',
        {   active: true,
            scope_org: this.org.ancestors(this.auth.user().ws_ou(), true)
        }, {atomic: true}
        ).toPromise().then(alerts => {
            this.alertTypes = alerts.map(a => ({id: a.id(), label: a.name()}));
        });
    }

    getCopies(): Promise<any> {

        // Avoid fetch if we're only adding notes to isnew copies.
        const ids = this.copyIds.filter(id => id > 0);
        if (ids.length === 0) { return Promise.resolve(); }

        return this.pcrud.search('acp', {id: this.copyIds}, {}, {atomic: true})
        .toPromise().then(copies => {
            this.copies = copies;
            copies.forEach(c => c.copy_alerts([]));
            if (this.mode === 'manage') {
                this.copy = copies[0];
            }
        });
    }

    // Copy alerts for the selected copies which have not been
    // acknowledged by staff and are within org unit range of
    // the alert type.
    getCopyAlerts(): Promise<any> {
        const typeIds = this.alertTypes.map(a => a.id);

        return this.pcrud.search('aca',
            {copy: this.copyIds, ack_time: null, alert_type: typeIds},
            {}, {atomic: true})
        .toPromise().then(alerts => {
            alerts.forEach(a => {
                const copy = this.copies.filter(c => c.id() === a.copy())[0];
                copy.copy_alerts().push(a);
            });
        });
    }

    getAlertTypeLabel(alert: IdlObject): string {
        const alertType = this.alertTypes.filter(t => t.id === alert.alert_type());
        return alertType[0].label;
    }

    removeAlert(alert: IdlObject) {
        // the only type of alerts we can remove are pending ones that
        // we have created during the lifetime of this modal; alerts
        // that already exist can only be cleared
        this.newAlerts = this.newAlerts.filter(t => t.id() !== alert.id());
    }

    // Add the in-progress new note to all copies.
    addNew() {
        if (!this.newAlert.alert_type()) { return; }

        this.newAlert.id(this.autoId--);
        this.newAlert.isnew(true);
        this.newAlerts.push(this.newAlert);

        this.newAlert = this.idl.create('aca');

    }

    applyChanges() {

        const changedAlerts = this.copy ?
            this.copy.copy_alerts().filter(a => a.ischanged()) :
            [];
        if (this.inPlaceCreateMode) {
            this.close({ newAlerts: this.newAlerts, changedAlerts: changedAlerts });
            return;
        }

        const alerts = [];
        this.newAlerts.forEach(alert => {
            this.copies.forEach(c => {
                const a = this.idl.clone(alert);
                a.isnew(true);
                a.id(null);
                a.copy(c.id());
                alerts.push(a);
            });
        });
        if (this.mode === 'manage') {
            changedAlerts.forEach(alert => {
                alerts.push(alert);
            });
        }
        this.pcrud.autoApply(alerts).toPromise().then(
            ok => {
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.close({ newAlerts: this.newAlerts, changedAlerts: changedAlerts });
            },
            err => this.errorMsg.current().then(msg => this.toast.danger(msg))
        );
    }
}
