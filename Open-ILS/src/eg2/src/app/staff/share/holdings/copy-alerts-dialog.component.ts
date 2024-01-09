import {Component, Input, ViewChild} from '@angular/core';
import {Observable, throwError, from} from 'rxjs';
import {switchMap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {StringComponent} from '@eg/share/string/string.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ServerStoreService} from '@eg/core/server-store.service';

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
    extends DialogComponent {

    @Input() copyIds: number[] = [];
    copies: IdlObject[];
    alertIdMap: { [key: number]: any };

    mode: string; // create | manage

    // If true, no attempt is made to save new alerts to the
    // database.  It's assumed this takes place in the calling code.
    @Input() inPlaceCreateMode = false;

    // This will not contain "real" alerts, but a deduped set of alert
    // proxies in a batch context that match on alert_type, temp, note,
    // and null/not-null for ack_time.
    alertsInCommon: IdlObject[] = [];

    alertTypes: ComboboxEntry[];
    newAlert: IdlObject;
    newAlerts: IdlObject[];
    autoId = -1;
    changesMade: boolean;
    defaultAlertType = 1; // default default :-)

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService,
        private serverStore: ServerStoreService) {
        super(modal); // required for subclassing
        this.copyIds = [];
        this.copies = [];
        this.alertIdMap = {};
    }

    prepNewAlert(): IdlObject {
        const newAlert = this.idl.create('aca');
        newAlert.alert_type(this.defaultAlertType);
        newAlert.create_staff(this.auth.user().id());
        return newAlert;
    }

    hasCopy(): Boolean {
        return this.copies.length > 0;
    }

    inBatch(): Boolean {
        return this.copies.length > 1;
    }

    /**
     * Fetch the item/record, then open the dialog.
     * Dialog promise resolves with true/false indicating whether
     * the mark-damanged action occured or was dismissed.
     */
    open(args: NgbModalOptions): Observable<CopyAlertsChanges> {
        this.copies = [];
        this.newAlerts = [];
        this.newAlert = this.prepNewAlert();

        if (this.copyIds.length === 0 && !this.inPlaceCreateMode) {
            return throwError('copy ID required');
        }

        // We're removing the distinction between 'manage' and 'create'
        // modes and are implementing batch edit for existing alerts
        // that match on alert_type, temp, note, and whether ack_time
        // is set or not set.
        this.mode = 'manage';

        // Observerify data loading
        const obs = from(
            this.getAlertTypes()
                .then(_ => this.getCopies())
                .then(_ => this.getCopyAlerts())
                .then(_ => this.getDefaultAlertType())
                .then(_ => { if (this.defaultAlertType) { this.newAlert.alert_type(this.defaultAlertType); } })
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
                    this.alertIdMap[a.id()] = a;
                    copy.copy_alerts().push(a);
                });
                if (this.inBatch()) {
                    let potentialMatches = this.copies[0].copy_alerts();

                    this.copies.slice(1).forEach(copy => {
                        potentialMatches = potentialMatches.filter(alertFromFirstCopy =>
                            copy.copy_alerts().some(alertFromCurrentCopy =>
                                this.compositeMatch(alertFromFirstCopy, alertFromCurrentCopy)
                            )
                        );
                    });

                    // potentialMatches now contains alerts that have a "match" in every copy
                    this.alertsInCommon = potentialMatches.map( match => this.cloneAlertForBatchProxy(match) );
                }
            });
    }

    getDefaultAlertType(): Promise<any> {
        // TODO fetching the default item alert type from holdings editor
        //      defaults had previously been handled via methods from
        //      VolCopyService. However, as described in LP#2044051, this
        //      caused significant issues with dependency injection.
        //      Consequently, some refactoring may be in order so that
        //      such default values can be managed via a more self-contained
        //      service.
        return this.serverStore.getItem('eg.cat.volcopy.defaults').then(
            (defaults) => {
                console.log('eg.cat.volcopy.defaults',defaults);
                if (defaults?.values?.item_alert_type) {
                    console.log('eg.cat.volcopy.defaults, got here for item_alert_type',defaults.values.item_alert_type);
                    this.defaultAlertType = defaults.values.item_alert_type;
                }
            }
        );
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

        this.newAlert.id(this.autoId--);
        this.newAlert.isnew(true);
        this.newAlerts.push(this.newAlert);

        this.newAlert = this.prepNewAlert();

    }

    compositeMatch(a: IdlObject, b: IdlObject): boolean {
        return a.alert_type() === b.alert_type()
            && a.temp() === b.temp()
            && a.note() === b.note()
            && (
                (a.ack_time() === null && b.ack_time() === null)
                    || (a.ack_time() !== null && b.ack_time() !== null)
            );
    }

    setAlert(target: IdlObject, source: IdlObject) {
        target.ack_staff(source.ack_staff());
        if (source.ack_time() === 'now') {
            target.ack_time('now');
            target.ack_staff(this.auth.user().id());
        }
        target.ischanged(true);
        target.alert_type(source.alert_type());
        target.temp(source.temp());
        target.ack_time(source.ack_time());
        target.note(source.note());
    }

    // clones everything but copy, create_time, and create_staff
    // This is serving as a reference alert for the other matching alerts
    cloneAlertForBatchProxy(source: IdlObject): IdlObject {
        const target = this.idl.create('aca');
        target.id( source.id() );
        target.alert_type(source.alert_type());
        target.temp(source.temp());
        target.ack_time(source.ack_time());
        target.ack_staff(source.ack_staff());
        target.note(source.note());
        return target;
    }

    applyChanges() {

        const changedAlerts = [];
        const changes = this.hasCopy()
            ? (
                this.inBatch()
                    ? this.alertsInCommon.filter(a => a.ischanged())
                    : this.copies[0].copy_alerts().filter(a => a.ischanged())
            )
            : [];
        console.log('applyChanges, changes', changes);

        changes.forEach(change => {
            if (this.inBatch()) {
                this.copies.forEach(copy => {
                    copy.copy_alerts().forEach(realAlert => {
                        // compare against the unchanged version of the reference alert
                        if (realAlert.id() !== change.id() && this.compositeMatch(realAlert, this.alertIdMap[ change.id() ])) {
                            this.setAlert(realAlert, change);
                            changedAlerts.push(realAlert);
                        }
                    });
                });
                // now change the original reference alert as well
                this.setAlert(this.alertIdMap[ change.id() ], change);
                changedAlerts.push( this.alertIdMap[ change.id() ] );
            } else {
                changedAlerts.push(change);
            }
        });

        if (this.inPlaceCreateMode) {
            this.close({ newAlerts: this.newAlerts, changedAlerts: changedAlerts });
            return;
        }
        console.log('changedAlerts.length, newAlerts.length', changedAlerts.length,this.newAlerts.length);
        const pendingAlerts = changedAlerts;

        this.newAlerts.forEach(alert => {
            this.copies.forEach(c => {
                const a = this.idl.clone(alert);
                a.isnew(true);
                a.id(null);
                a.copy(c.id());
                pendingAlerts.push(a);
            });
        });

        this.pcrud.autoApply(pendingAlerts).toPromise().then(
            ok => {
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.close({ newAlerts: this.newAlerts, changedAlerts: changedAlerts });
            },
            err => {
                this.errorMsg.current().then(msg => this.toast.danger(msg));
                console.error('pcrud error', err);
            }
        );
    }
}
