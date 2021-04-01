import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, empty} from 'rxjs';
import {switchMap, tap} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/* Apply notification changes to affected holds */

export interface HoldNotifyMod {
    field: string,
    newValue: any,
    oldValue: any,
    holds: any[]
}

@Component({
  selector: 'eg-hold-notify-update-dialog',
  templateUrl: 'hold-notify-update.component.html'
})

export class HoldNotifyUpdateDialogComponent
    extends DialogComponent implements OnInit {

    // Values provided directly by our parent component
    smsCarriers: ComboboxEntry[];
    mods: HoldNotifyMod[] = [];

    selected: {[field: string]: boolean} = {};

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

    applyChanges() {
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
}


