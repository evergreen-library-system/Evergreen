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

@Component({
  selector: 'eg-copy-alerts-dialog',
  templateUrl: 'copy-alerts-dialog.component.html'
})

export class CopyAlertsDialogComponent
    extends DialogComponent implements OnInit {

    _copyIds: number[];
    @Input() set copyIds(ids: number[]) {
        this._copyIds = [].concat(ids);
    }
    get copyIds(): number[] {
        return this._copyIds;
    }

    _mode: string; // create | manage
    @Input() set mode(m: string) {
        this._mode = m;
    }
    get mode(): string {
        return this._mode;
    }

    // In 'create' mode, we may be adding notes to multiple copies.
    copies: IdlObject[];
    // In 'manage' mode we only handle a single copy.
    copy: IdlObject;
    alertTypes: ComboboxEntry[];
    newAlert: IdlObject;
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
    open(args: NgbModalOptions): Observable<boolean> {
        this.copy = null;
        this.copies = [];
        this.newAlert = this.idl.create('aca');
        this.newAlert.create_staff(this.auth.user().id());

        if (this.copyIds.length === 0) {
            return throwError('copy ID required');
        }

        // In manage mode, we can only manage a single copy.
        // But in create mode, we can add alerts to multiple copies.

        if (this.mode === 'manage') {
            if (this.copyIds.length > 1) {
                console.warn('Attempt to manage alerts for multiple copies.');
                this.copyIds = [this.copyIds[0]];
            }
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
        if (this.alertTypes) {
            return Promise.resolve();
        }
        return this.pcrud.retrieveAll('ccat',
        {   active: true,
            scope_org: this.org.ancestors(this.auth.user().ws_ou(), true)
        }, {atomic: true}
        ).toPromise().then(alerts => {
            this.alertTypes = alerts.map(a => ({id: a.id(), label: a.name()}));
        });
    }

    getCopies(): Promise<any> {
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
        const copyIds = this.copies.map(c => c.id());
        const typeIds = this.alertTypes.map(a => a.id);

        return this.pcrud.search('aca',
            {copy: copyIds, ack_time: null, alert_type: typeIds},
            {}, {atomic: true})
        .toPromise().then(alerts => {
            alerts.forEach(a => {
                const copy = this.copies.filter(c => c.id() === a.copy())[0];
                copy.copy_alerts().push(a);
            });
        });
    }

    // Add the in-progress new note to all copies.
    addNew() {
        if (!this.newAlert.alert_type()) { return; }

        const alerts: IdlObject[] = [];
        this.copies.forEach(c => {
            const a = this.idl.clone(this.newAlert);
            a.copy(c.id());
            alerts.push(a);
        });

        this.pcrud.create(alerts).toPromise().then(
            newAlert => {
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.changesMade = true;
                if (this.mode === 'create') {
                    // In create mode, we assume the user wants to create
                    // a single alert and be done with it.
                    this.close(this.changesMade);
                } else {
                    // Otherwise, add the alert to the copy
                    this.copy.copy_alerts().push(newAlert);
                }
            },
            err => {
                this.errorMsg.current().then(msg => this.toast.danger(msg));
            }
        );
    }

    applyChanges() {
        const alerts = this.copy.copy_alerts().filter(a => a.ischanged());
        if (alerts.length === 0) { return; }
        this.pcrud.update(alerts).toPromise().then(
            ok => this.successMsg.current().then(msg => this.toast.success(msg)),
            err => this.errorMsg.current().then(msg => this.toast.danger(msg))
        );
    }
}

