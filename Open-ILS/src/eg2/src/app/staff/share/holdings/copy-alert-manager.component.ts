import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, throwError, from} from 'rxjs';
import {concatMap} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {HoldingsService} from './holdings.service';
import {CopyAlertsDialogComponent} from '@eg/staff/share/holdings/copy-alerts-dialog.component';

/**
 * Dialog for managing copy alerts.
 */

@Component({
    selector: 'eg-copy-alert-manager',
    templateUrl: 'copy-alert-manager.component.html',
    styles: ['.acknowledged {text-decoration: line-through }']
})

export class CopyAlertManagerDialogComponent extends DialogComponent {

    mode: string;
    alerts: IdlObject[];
    nextStatuses: IdlObject[];
    nextStatus: number;
    newAlertsAdded = false;

    @ViewChild('copyAlertsDialog') private copyAlertsDialog: CopyAlertsDialogComponent;

    constructor(
        private modal: NgbModal,
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService,
        private strings: StringService,
        private holdings: HoldingsService
    ) { super(modal); console.log('CopyAlertManagerDialogComponent, this',this); }

    open(ops?: NgbModalOptions): Observable<any> {

        this.nextStatus = null;
        this.newAlertsAdded = false;

        let promise = Promise.resolve(null);
        this.alerts.forEach(copyAlert =>
            promise = promise.then(_ => this.ingestAlert(copyAlert)));

        return from(promise).pipe(concatMap(_ => super.open(ops)));
    }

    ingestAlert(copyAlert: IdlObject): Promise<any> {
        let promise = Promise.resolve(null);

        const state = copyAlert.alert_type().state();
        copyAlert._event = copyAlert.alert_type().event();

        if (copyAlert.note()) {
            copyAlert._message = copyAlert.note();
        } else {
            const key = `staff.holdings.copyalert.${copyAlert._event}.${state}`;
            promise = promise.then(_ => {
                return this.strings.interpolate(key)
                    .then(str => copyAlert._message = str);
            });
        }

        const nextStatuses: number[] = [];
        this.nextStatuses = [];

        if (copyAlert.temp() === 'f') { return promise; }

        if (copyAlert.alert_type().next_status()) {
            copyAlert.alert_type().next_status().forEach(statId => {
                if (!nextStatuses.includes(statId)) {
                    nextStatuses.push(statId);
                }
            });
        }

        if (this.mode === 'checkin' && nextStatuses.length > 0) {

            promise = promise.then(_ => this.holdings.getCopyStatuses())
                .then(statMap => {
                    nextStatuses.forEach(statId => {
                        const wanted = statMap[statId];
                        if (wanted) { this.nextStatuses.push(wanted); }
                    });

                    if (this.nextStatuses.length > 0) {
                        this.nextStatus = this.nextStatuses[0].id();
                    }
                });
        }

        return promise;
    }

    canBeAcked(copyAlert: IdlObject): boolean {
        return !copyAlert.ack_time() && copyAlert.temp() === 't';
    }

    canBeRemoved(copyAlert: IdlObject): boolean {
        return !copyAlert.ack_time() && copyAlert.temp() === 'f';
    }

    isAcked(copyAlert: IdlObject): boolean {
        return copyAlert._acked;
    }

    ok() {
        this.newAlertsAdded = false;
        const acks: IdlObject[] = [];
        this.alerts.forEach(copyAlert => {

            if (copyAlert._acked) {
                copyAlert.ack_time('now');
                copyAlert.ack_staff(this.auth.user().id());
                copyAlert.ischanged(true);
                acks.push(copyAlert);
            }

            if (acks.length > 0) {
                this.pcrud.update(acks).toPromise()
                    .then(_ => this.close({nextStatus: this.nextStatus}));
            } else {
                this.close({nextStatus: this.nextStatus});
            }
        });
    }

    openItemAlerts() {
        const copyIds = [ this.alerts[0].copy() ];
        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.open({size: 'lg'}).subscribe(
            changes => {
                if (!changes) { return; }
                if (changes.newThings.length > 0 || changes.changedThings.length > 0) {
                    this.newAlertsAdded = true;
                }
            }
        );
    }
}

