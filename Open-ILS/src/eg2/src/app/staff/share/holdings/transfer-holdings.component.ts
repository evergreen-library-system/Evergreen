import {Component, OnInit, Input, ViewChild, Renderer2} from '@angular/core';
import {Observable} from 'rxjs';
import {switchMap, map, tap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';

/* Transfer holdings (AKA asset.call_number) to a target bib record. */

@Component({
  selector: 'eg-transfer-holdings',
  templateUrl: 'transfer-holdings.component.html'
})

export class TransferHoldingsComponent implements OnInit {

    // Array of 'acn' objects.
    // Assumes all acn's are children of the same bib record.
    @Input() callNums: IdlObject[];

    // Required field.
    // All call numbers will be transferred to this record ID.
    @Input() targetRecId: number;

    // Optional.  If set, all call numbers will transfer to this org
    // unit (owning lib) in addition to transfering to the select bib
    // record.
    @Input() targetOrgId: number;

    @ViewChild('successMsg', {static: false})
        private successMsg: StringComponent;

    @ViewChild('noTargetMsg', {static: false})
        private noTargetMsg: StringComponent;

    @ViewChild('alertDialog', {static: false})
        private alertDialog: AlertDialogComponent;

    @ViewChild('progressDialog', {static: false})
        private progressDialog: ProgressDialogComponent;

    eventDesc: string;

    constructor(
        private toast: ToastService,
        private net: NetService,
        private auth: AuthService,
        private evt: EventService) {}

    ngOnInit() {}

    // Resolves with true if transfer completed, false otherwise.
    // Assumes all volumes are transferred to the same bib record.
    transferHoldings(): Promise<Boolean> {
        if (!this.callNums || this.callNums.length === 0) {
            return Promise.resolve(false);
        }

        if (!this.targetRecId) {
            this.toast.warning(this.noTargetMsg.text);
            return Promise.resolve(false);
        }

        this.eventDesc = '';

        // Group the transfers by owning library.
        const transferVols: {[orgId: number]: number[]} = {};

        if (this.targetOrgId) {

            // Transfering all call numbers to the same bib record
            // and owning library.
            transferVols[+this.targetOrgId] = this.callNums.map(cn => cn.id());

        } else {

            // Transfering all call numbers to the same bib record
            // while retaining existing owning library.
            this.callNums.forEach(cn => {
                const orgId = Number(cn.owning_lib());
                if (!transferVols[orgId]) { transferVols[orgId] = []; }
                transferVols[orgId].push(cn.id());
            });
        }

        this.progressDialog.update({
            value: 0,
            max: Object.keys(transferVols).length
        });
        this.progressDialog.open();

        return this.performTransfers(transferVols)
        .then(res => {
            this.progressDialog.close();
            return res;
        });
    }

    performTransfers(transferVols: any): Promise<Boolean> {
        const orgId = Object.keys(transferVols)[0];
        const volIds = transferVols[orgId];

        // Avoid re-processing
        delete transferVols[orgId];

        // Note the AngJS client also assumes .override.
        const method = 'open-ils.cat.asset.volume.batch.transfer.override';

        return this.net.request('open-ils.cat', method, this.auth.token(), {
            docid: this.targetRecId,
            lib: orgId,
            volumes: volIds
        }).toPromise().then(resp => {
            const evt = this.evt.parse(resp);

            if (evt || Number(resp) !== 1) {
                console.warn(resp);
                this.eventDesc = evt ? evt.desc : '';

                // Failure -- stop short there to avoid alert storm.
                return this.alertDialog.open().toPromise()
                .then(_ => { this.eventDesc = ''; return false; });
            }

            this.progressDialog.increment();

            if (Object.keys(transferVols).length > 0) {
                return this.performTransfers(transferVols);
            }

            return true; // All done
        });
    }
}



