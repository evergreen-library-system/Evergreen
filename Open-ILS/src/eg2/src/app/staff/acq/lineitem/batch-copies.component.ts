import {Component, OnInit, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {LineitemCopyAttrsComponent} from './copy-attrs.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {CancelDialogComponent} from './cancel-dialog.component';

const BATCH_FIELDS = [
    'owning_lib',
    'location',
    'collection_code',
    'fund',
    'circ_modifier',
    'cn_label'
];

@Component({
  templateUrl: 'batch-copies.component.html',
  selector: 'eg-lineitem-batch-copies',
  styleUrls: ['batch-copies.component.css']
})
export class LineitemBatchCopiesComponent implements OnInit {

    @Input() lineitem: IdlObject;

    @ViewChild('confirmAlertsDialog') confirmAlertsDialog: ConfirmDialogComponent;
    @ViewChild('cancelDialog') cancelDialog: CancelDialogComponent;

    // Current alert that needs confirming
    alertText: IdlObject;

    constructor(
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {}

    // Propagate values from the batch edit bar into the indivudual LID's
    batchApplyAttrs(copyTemplate: IdlObject) {
        BATCH_FIELDS.forEach(field => {
            const val = copyTemplate[field]();
            if (val === undefined) { return; }
            this.lineitem.lineitem_details().forEach(copy => {
                copy[field](val);
                copy.ischanged(true); // isnew() takes precedence
            });
        });
    }

    deleteCopy(copy: IdlObject) {
        if (copy.isnew()) {
            // Brand new copies can be discarded
            this.lineitem.lineitem_details(
                this.lineitem.lineitem_details().filter(c => c.id() !== copy.id())
            );
        } else {
            // Requires a Save Changes action.
            copy.isdeleted(true);
        }
    }

    refreshLineitem() {
        this.liService.getFleshedLineitems([this.lineitem.id()], {toCache: true})
        .subscribe(liStruct => this.lineitem = liStruct.lineitem);
    }

    handleActionResponse(resp: any) {
        const evt = this.evt.parse(resp);
        if (evt) {
          alert(evt);
        } else if (resp) {
            this.refreshLineitem();
        }
    }

    cancelCopy(copy: IdlObject) {
        this.cancelDialog.open().subscribe(reason => {
            if (!reason) { return; }
            this.net.request('open-ils.acq',
                'open-ils.acq.lineitem_detail.cancel',
                this.auth.token(), copy.id(), reason
            ).subscribe(ok => this.handleActionResponse(ok));
        });
    }

    receiveCopy(copy: IdlObject) {
        this.checkLiAlerts().then(ok => {
            this.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem_detail.receive',
                this.auth.token(), copy.id()
            ).subscribe(ok2 => this.handleActionResponse(ok2));
        }, err => {}); // avoid console errors
    }

    unReceiveCopy(copy: IdlObject) {
        this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem_detail.receive.rollback',
            this.auth.token(), copy.id()
        ).subscribe(ok => this.handleActionResponse(ok));
    }

    checkLiAlerts(): Promise<boolean> {

        let promise = Promise.resolve(true);

        const notes = this.lineitem.lineitem_notes().filter(note =>
            note.alert_text() && !this.liService.alertAcks[note.id()]);

        if (notes.length === 0) { return promise; }

        notes.forEach(n => {
            promise = promise.then(_ => {
                this.alertText = n.alert_text();
                return this.confirmAlertsDialog.open().toPromise().then(ok => {
                    if (!ok) { return Promise.reject(); }
                    this.liService.alertAcks[n.id()] = true;
                    return true;
                });
            });
        });

        return promise;
    }

    hasEditableCopies(): boolean {
        if (this.lineitem) {
            const copies = this.lineitem.lineitem_details();
            if (copies && copies.length > 0) {
                for (let idx = 0; idx < copies.length; idx++) { // early break
                    if (this.liService.copyDisposition(
                        this.lineitem, copies[idx]) === 'pre-order') {
                        return true;
                    }
                }
            }
        }
        return false;
    }
}


