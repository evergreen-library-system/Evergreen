import {Component, OnInit, Input, ViewChild, Renderer2} from '@angular/core';
import {Observable} from 'rxjs';
import {switchMap, map, tap} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {StringComponent} from '@eg/share/string/string.component';

/* Transfer items to a call number. */

@Component({
  selector: 'eg-transfer-items',
  templateUrl: 'transfer-items.component.html'
})

export class TransferItemsComponent implements OnInit {

    @ViewChild('successMsg', {static: false})
        private successMsg: StringComponent;

    @ViewChild('errorMsg', {static: false})
        private errorMsg: StringComponent;

    @ViewChild('noTargetMsg', {static: false})
        private noTargetMsg: StringComponent;

    @ViewChild('confirmDialog', {static: false})
        private confirmDialog: ConfirmDialogComponent;

    @ViewChild('alertDialog', {static: false})
        private alertDialog: AlertDialogComponent;

    eventDesc: string;

    constructor(
        private toast: ToastService,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private evt: EventService) {}

    ngOnInit() {}

    // Transfers a set of items/copies (by ID) to the selected call
    // number (by ID).
    // Resolves with true if transfer completed, false otherwise.
    transferItems(itemIds: number[],
        cnId: number, override?: boolean): Promise<boolean> {

        this.eventDesc = '';

        let method = 'open-ils.cat.transfer_copies_to_volume';
        if (override) { method += '.override'; }

        return this.net.request('open-ils.cat',
            method, this.auth.token(), cnId, itemIds)
        .toPromise().then(resp => {

            const evt = this.evt.parse(resp);

            if (evt) {

                if (override) {
                    // Override failed, no looping please.
                    this.toast.warning(this.errorMsg.text);
                    return false;
                }

                this.eventDesc = evt.desc;

                return this.confirmDialog.open().toPromise().then(ok =>
                    ok ? this.transferItems(itemIds, cnId, true) : false);

            } else { // success

                this.toast.success(this.successMsg.text);
                return true;
            }
        });
    }

    // Transfers a set of items/copies (by object with fleshed call numbers)
    // to the selected record and org unit ID, creating new call numbers
    // where needed.
    // Resolves with true if transfer completed, false otherwise.
    autoTransferItems(items: IdlObject[], // acp with fleshed call_number's
        recId: number, orgId: number): Promise<Boolean> {

        this.eventDesc = '';

        const cnTransfers: any = {};
        const itemTransfers: any = {};

        items.forEach(item => {
            const cn = item.call_number();

            if (cn.owning_lib() !== orgId || cn.record() !== recId) {
                cn.owning_lib(orgId);
                cn.record(recId);

                if (cnTransfers[cn.id()]) {
                    itemTransfers[cn.id()].push(item.id());

                } else {
                    cnTransfers[cn.id()] = cn;
                    itemTransfers[cn.id()] = [item.id()];
                }
            }
        });

        return this.transferCallNumbers(cnTransfers, itemTransfers);
    }

    transferCallNumbers(cnTransfers, itemTransfers): Promise<boolean> {

        const cnId = Object.keys(cnTransfers)[0];
        const cn = cnTransfers[cnId];
        delete cnTransfers[cnId];

        return this.net.request('open-ils.cat',
            'open-ils.cat.call_number.find_or_create',
            this.auth.token(),
            cn.label(),
            cn.record(),     // may be new
            cn.owning_lib(), // may be new
            (typeof cn.prefix() === 'object' ? cn.prefix().id() : cn.prefix()),
            (typeof cn.suffix() === 'object' ? cn.suffix().id() : cn.suffix()),
            cn.label_class()

        ).toPromise().then(resp => {

            const evt = this.evt.parse(resp);

            if (evt) {
                // Problem.  Stop processing.
                this.toast.warning(this.errorMsg.text);
                this.eventDesc = evt.desc;
                return this.alertDialog.open().toPromise().then(_ => false);
            }

            return this.transferItems(itemTransfers[cn.id()], resp.acn_id)
            .then(ok => {

                if (ok && Object.keys(cnTransfers).length > 0) {
                    // More call numbers to transfer.
                    return this.transferCallNumbers(cnTransfers, itemTransfers);
                }

                return ok;
            });
        });
    }
}



