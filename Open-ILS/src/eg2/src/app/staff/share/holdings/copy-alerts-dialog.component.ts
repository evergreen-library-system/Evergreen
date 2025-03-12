import { Component, Input, Directive, HostBinding } from '@angular/core';
import { Observable } from 'rxjs';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { ToastService } from '@eg/share/toast/toast.service';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import { AuthService } from '@eg/core/auth.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import {FormsModule, AbstractControl, NG_VALIDATORS, ValidationErrors, Validator, Validators, ValidatorFn} from '@angular/forms';
import { ComboboxComponent, ComboboxEntry } from '@eg/share/combobox/combobox.component';
import {VolCopyContext} from '@eg/staff/cat/volcopy/volcopy';
import {
    CopyThingsDialogComponent,
    IThingObject,
    IThingChanges,
    IThingConfig
} from './copy-things-dialog.component';

export interface ICopyAlert extends IThingObject {
    alert_type(val?: number): number;
    temp(val?: boolean): boolean;
    note(val?: string): string;
    ack_time(val?: any): any;
    ack_staff(val?: number): number;
    copy(val?: number): number;
    create_staff(val?: number): number;
    create_time(val?: any): any;
}

interface ProxyAlert extends ICopyAlert {
    originalAlertIds: number[];
}

export interface ICopyAlertChanges extends IThingChanges<ICopyAlert> {
    newThings: ICopyAlert[];
    changedThings: ICopyAlert[];
    deletedThings: ICopyAlert[];
}

@Component({
    selector: 'eg-copy-alerts-dialog',
    templateUrl: 'copy-alerts-dialog.component.html'
})
export class CopyAlertsDialogComponent extends
    CopyThingsDialogComponent<ICopyAlert, ICopyAlertChanges> {

    protected thingType = 'alerts';
    protected successMessage = $localize`Successfully Modified Item Alerts`;
    protected errorMessage = $localize`Failed To Modify Item Alerts`;
    protected batchWarningMessage =
        $localize`Note that items in batch do not share alerts directly. Displayed alerts represent matching alert groups.`;

    context: VolCopyContext;

    // Alert-specific properties
    alertTypes: ComboboxEntry[];
    activeAlertTypes: ComboboxEntry[];
    disabledAlertTypes: any[] = [];
    defaultAlertType = 1;
    alertIdMap: { [key: number]: (IdlObject|ICopyAlert) } = {};

    alertsInCommon: ICopyAlert[] = [];
    newAlert: ICopyAlert;

    alerts: IdlObject[] = [];

    constructor(
        modal: NgbModal,
        toast: ToastService,
        idl: IdlService,
        pcrud: PcrudService,
        org: OrgService,
        auth: AuthService,
        private serverStore: ServerStoreService
    ) {
        const config: IThingConfig<ICopyAlert> = {
            idlClass: 'aca',
            thingField: 'copy_alerts',
            defaultValues: {
                alert_type: 1,
                create_staff: auth.user().id(),
                temp: false
            }
        };
        super(modal, toast, idl, pcrud, org, auth, config);
        this.newAlert = this.createNewThing();
        this.context = new VolCopyContext();
        this.context.org = org; // inject
        this.context.idl = idl; // inject
    }

    protected createNewThing(): ICopyAlert {
        const alert = super.createNewThing();
        alert.alert_type(this.defaultAlertType);
        return alert;
    }

    public async initialize(): Promise<void> {
        await this.getAlertTypes();
        await this.getDefaultAlertType();
        if (!this.newAlert) {
            this.newAlert = this.createNewThing();
        }
        // console.debug('CopyAlertsDialogComponent, initialize()');
        await super.initialize();
    }

    private async getAlertTypes(): Promise<void> {
        if (this.alertTypes) { return; }

        const alertTypes = await this.pcrud.retrieveAll('ccat',
            {
                // active: true,
                scope_org: this.org.ancestors(this.auth.user().ws_ou(), true),
                order_by: {ccat: 'name'}
            },
            { atomic: true }
        ).toPromise();

        this.disabledAlertTypes = alertTypes.filter(a => a.active() === 'f' || a.active() === false).map(a => a.id());
        this.activeAlertTypes = alertTypes.filter(a => a.active() === 't' || a.active() === true).map(a => ({
            id: a.id(),
            label: a.name()
        }));

        this.alertTypes = alertTypes.map(a => ({
            id: a.id(),
            label: a.name()
        }));
    }

    private getCurrentAlertTypes(currentAlertType) {
        if (this.disabledAlertTypes.includes(currentAlertType)) {
            return this.activeAlertTypes.concat(this.alertTypes.find(t => t.id === currentAlertType));
        }

        return this.activeAlertTypes;
    }

    private getDisabledAlertTypes(currentAlertType) {
        if (this.disabledAlertTypes.includes(currentAlertType)) {
            return Array(currentAlertType);
        }

        return;
    }

    private async getDefaultAlertType(): Promise<void> {
        const defaults = await this.serverStore.getItem('eg.cat.volcopy.defaults');
        if (defaults?.values?.thing_alert_type) {
            this.defaultAlertType = defaults.values.thing_alert_type;
            if (this.newAlert) {
                this.newAlert.alert_type(this.defaultAlertType);
            }
        }
    }

    protected async getThings(): Promise<void> {
        if (this.copyIds.length === 0) { return; }
        if (this.alerts.length > 0) {
            // console.debug('already have alerts, trimming newThings from existing. newThings=', this.newThings);
            this.copies.forEach( c => {
                const newThingIds = this.newThings.map( aa => aa.id() );
                c.copy_alerts(
                    (c.copy_alerts() || []).filter( a => !newThingIds.includes(a.id()) )
                );
            });
            return;
        } // need to make sure this is cleared after a save. It is; the page reloads

        const query = {
            copy: this.copyIds,
            ack_time: null,
            alert_type: this.alertTypes.map(a => a.id)
        };
        this.alerts = await this.pcrud.search('aca',
            query,
            {},
            { atomic: true }
        ).toPromise();

        this.copies.forEach(c => c.copy_alerts([]));
        this.alerts.forEach(copy_alert => {
            const copy = this.copies.find(c => c.id() === copy_alert.copy());
            copy.copy_alerts( copy.copy_alerts().concat(copy_alert) );
        });
    }

    protected async processCommonThings(): Promise<void> {
        if (!this.inBatch()) { return; }

        let potentialMatches = this.copies[0].copy_alerts();

        // Find alerts that match across all copies
        this.copies.slice(1).forEach(copy => {
            potentialMatches = potentialMatches.filter(alertFromFirstCopy =>
                copy.copy_alerts().some(alertFromCurrentCopy =>
                    this.compositeMatch(alertFromFirstCopy, alertFromCurrentCopy)
                )
            );
        });

        this.alertsInCommon = potentialMatches.map(match => {
            const proxy = this.cloneAlertForBatchProxy(match) as ProxyAlert;
            // Collect IDs of all matching alerts across all copies
            proxy.originalAlertIds = [];
            this.copies.forEach(copy => {
                copy.copy_alerts().forEach(alert => {
                    if (this.compositeMatch(alert, match)) {
                        proxy.originalAlertIds.push(alert.id());
                    }
                });
            });
            return proxy;
        });
    }

    protected compositeMatch(a: ICopyAlert, b: ICopyAlert): boolean {
        return a.alert_type() === b.alert_type() &&
            a.temp() === b.temp() &&
            a.note() === b.note() &&
            Boolean(a.ack_time()) === Boolean(b.ack_time());
    }

    private cloneAlertForBatchProxy(source: ICopyAlert): ICopyAlert {
        const target = this.createNewThing();
        target.id(source.id());
        target.alert_type(source.alert_type());
        target.temp(source.temp());
        target.ack_time(source.ack_time());
        target.ack_staff(source.ack_staff());
        target.note(source.note());
        target.isnew(source.isnew());
        return target;
    }

    getAlertTypeLabel(alert: ICopyAlert): string {
        const alertType = this.alertTypes?.find(t => t.id === alert.alert_type());
        return alertType ? alertType.label : '';
    }

    addNew(): void {
        if (!this.validate()) { return; }

        this.newAlert.id(this.autoId--);
        this.newAlert.isnew(true);
        this.newThings.push(this.newAlert);
        this.newAlert = this.createNewThing();
    }

    undeleteNote(alert: ICopyAlert): void {
        alert.isdeleted( alert.isdeleted() ?? false );
        // console.debug('undeleteAlert, alert, alert.isdeleted()', alert, alert.isdeleted());
        super.removeThing([alert]); // it's a toggle
    }

    removeAlert(alert: ICopyAlert): void {
        alert.isdeleted( alert.isdeleted() ?? false );
        // console.debug('removeAlert, alert, alert.isdeleted()', alert, alert.isdeleted());
        super.removeThing([alert]);
    }

    protected validate(): boolean {
        const form = document.getElementById('new-alert-form') as HTMLFormElement;
        const typeInput = document.getElementById('item-alert-type') as HTMLFormElement;
        const typeError = document.getElementById('item-alert-type-error') as HTMLElement;

        form.classList.add('form-validated');

        if (!this.newAlert.alert_type()) {
            typeError.removeAttribute('hidden');
            setTimeout(() => typeInput.focus());
            // this.toast.danger($localize`Alert type is required`);
            return false;
        }
        typeError.setAttribute('hidden', '');
        return true;
    }

    setAck(alert, $event) {
        // (ngModelChange)="alert.ack_time($event ? 'now' : null); alert.ischanged(true)"
        if ($event) {
            // console.debug('setAck clear',alert,$event);
            alert.ack_time('now');
            alert.ack_staff(this.auth.user().id());
        } else {
            // console.debug('setAck reset',alert,$event);
            alert.ack_time(null);
            alert.ack_staff(null);
        }
        alert.ischanged(true);
    }

    protected async applyChanges(): Promise<void> {
        try {
            // console.debug('CopyAlertsDialog, applyChanges, changedThings prior to rebuild', this.changedThings);
            // console.debug('CopyAlertsDialog, applyChanges, deletedThings prior to rebuild', this.deletedThings);
            // console.debug('CopyAlertsDialog, applyChanges, copies', this.copies);
            this.changedThings = [];
            this.deletedThings = [];

            // Find alerts that have been modified
            if (this.inBatch()) {
                // For batch mode, look at alertsInCommon for changes
                this.changedThings = this.alertsInCommon.filter(alert => alert.ischanged());
                this.deletedThings = this.alertsInCommon.filter(alert => alert.isdeleted());
                // console.debug('CopyAlertsDialog, applyChanges, changedThings rebuilt in batch context', this.changedThings);
                // console.debug('CopyAlertsDialog, applyChanges, deletedThings rebuilt in batch context', this.deletedThings);
            } else if (this.copies.length) {
                // For single mode, look at the copy's alerts
                this.changedThings = this.copies[0].copy_alerts()
                    .filter(alert => alert.ischanged());
                this.deletedThings = this.copies[0].copy_alerts()
                    .filter(alert => alert.isdeleted());
                // console.debug('CopyAlertsDialog, applyChanges, changedThings rebuilt in non-batch context', this.changedThings);
                // console.debug('CopyAlertsDialog, applyChanges, deletedThings rebuilt in non-batch context', this.deletedThings);
            } else {
                // console.debug('CopyAlertsDialog, applyChanges, inBatch() == false and this.copies.length == false');
            }

            if (this.inPlaceCreateMode) {
                this.close(this.gatherChanges());
                return;
            }

            console.log('here', this);

            this.context.newAlerts = this.newThings;
            this.context.changedAlerts = this.changedThings;
            this.context.deletedAlerts = this.deletedThings;

            this.copies.forEach( c => this.context.updateInMemoryCopyWithAlerts(c) );

            console.log('copies', this.copies);

            // Handle persistence ourselves
            const result = await this.saveChanges();
            // console.debug('CopyAlertsDialogComponent, saveChanges() result', result);
            if (result) {
                this.showSuccess();
                this.alerts = []; this.copies = []; this.copyIds = [];
                this.close(this.gatherChanges());
            } else {
                this.showError('saveChanges failed');
            }
        } catch (err) {
            this.showError(err);
        }
    }
}

export function inactiveEntry(): ValidatorFn {
    return (control: AbstractControl): { [key: string]: any } | null =>
        this.combobox.disableEntries.includes(control.value)
            ? {inactiveEntry: control.value} : null;
}

@Directive({
// eslint-disable-next-line @angular-eslint/directive-selector
    selector: '[validateDisabledSelection]',
    providers: [{ provide: NG_VALIDATORS, useExisting: AlertTypeValidatorDirective, multi: true }]
})

export class AlertTypeValidatorDirective implements Validator {

    constructor(private combobox: ComboboxComponent) {}

    validate(control: AbstractControl): { [key: string]: any } | null {
        return inactiveEntry()(control);
    }
}
