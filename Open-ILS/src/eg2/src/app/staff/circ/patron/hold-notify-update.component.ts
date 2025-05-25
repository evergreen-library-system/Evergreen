import {Component, OnInit} from '@angular/core';
import {from, filter, concatMap} from 'rxjs';
import {IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/* Apply notification changes to affected holds */

export interface HoldNotifyMod {
    field: string;
    newValue: any;
    oldValue: any;
    holds: any[];
}

@Component({
    selector: 'eg-hold-notify-update-dialog',
    templateUrl: 'hold-notify-update.component.html'
})

export class HoldNotifyUpdateDialogComponent
    extends DialogComponent implements OnInit {

    // Values provided directly by our parent component
    patronId: number;
    smsCarriers: ComboboxEntry[];
    mods: HoldNotifyMod[] = [];
    defaultCarrier: number;

    selected: {[field: string]: boolean} = {};
    loading = false;

    constructor(
        private modal: NgbModal,
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private evt: EventService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService) {
        super(modal);
    }

    isPhoneChange(mod: HoldNotifyMod): boolean {
        return mod.field.match(/_phone/) !== null;
    }

    isBoolChange(mod: HoldNotifyMod): boolean {
        return mod.field.match(/_notify/) !== null && !this.isCarrierChange(mod);
    }

    isCarrierChange(mod: HoldNotifyMod): boolean {
        return mod.field.match(/carrier/) !== null;
    }

    carrierName(id: number): string {
        const entry = this.smsCarriers.filter(e => e.id === id)[0];
        return entry ? entry.label : '';
    }

    anySelected(): boolean {
        return Object.values(this.selected).filter(v => v).length > 0;
    }

    applyChanges() {
        this.loading = true;

        from(Object.keys(this.selected))
            .pipe(filter(field => this.selected[field] === true))
            .pipe(concatMap(field => {

                const mod = this.mods.filter(m => m.field === field)[0];
                const holdIds = mod.holds.map(h => h.id);
                const carrierId = mod.field === 'default_sms' ?  this.defaultCarrier : null;

                return this.net.request(
                    'open-ils.circ',
                    'open-ils.circ.holds.batch_update_holds_by_notify_staff',
                    this.auth.token(), this.patronId, holdIds, mod.oldValue,
                    mod.newValue, mod.field, carrierId
                );

            }))
            .subscribe(
                { next: resp => console.log('GOT', resp), error: (err: unknown) => console.error(err), complete: () => {
                    this.loading = false;
                    this.close();
                } }
            );
    }
}


