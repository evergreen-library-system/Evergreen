import {Component, OnInit, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {CancelDialogComponent} from './cancel-dialog.component';
import {LineitemAlertDialogComponent} from './lineitem-alert-dialog.component';

const BATCH_FIELDS = [
    'owning_lib',
    'location',
    'collection_code',
    'fund',
    'circ_modifier',
    'cn_label',
    'note'
];

@Component({
    templateUrl: 'batch-copies.component.html',
    selector: 'eg-lineitem-batch-copies',
    styleUrls: ['batch-copies.component.css']
})
export class LineitemBatchCopiesComponent implements OnInit {

    @Input() lineitem: IdlObject;
    @Input() batchAdd = false;
    @Input() hideBarcode = false;

    @Output() becameDirty = new EventEmitter<Boolean>();

    @ViewChild('confirmAlertsDialog') confirmAlertsDialog: LineitemAlertDialogComponent;
    @ViewChild('cancelDialog') cancelDialog: CancelDialogComponent;

    // Current alert that needs confirming
    alertText: IdlObject;
    liId: number;
    liTitle: string;
    alertComment: string;

    constructor(
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {
        if (!this.lineitem) {
            this.lineitem = this.idl.create('jub');
            const copy = this.idl.create('acqlid');
            copy.isnew(true);
            this.lineitem.lineitem_details([copy]);
        }
    }

    // Propagate values from the batch edit bar into the indivudual LID's
    batchApplyAttrs(copyTemplate: IdlObject) {
        BATCH_FIELDS.forEach(field => {
            const val = copyTemplate[field]();
            if (val === undefined || val === null) { return; }
            this.lineitem.lineitem_details().forEach(copy => {
                copy[field](val);
                copy.ischanged(true); // isnew() takes precedence
                this.becameDirty.emit(true);
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
            this.becameDirty.emit(true);
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
            // eslint-disable-next-line rxjs/no-nested-subscribe
            ).subscribe(ok => this.handleActionResponse(ok));
        });
    }

    receiveCopy(copy: IdlObject) {
        this.liService.checkLiAlerts([this.lineitem], this.confirmAlertsDialog).then(ok => {
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

    copies(): IdlObject[] {
        return this.lineitem.lineitem_details().filter(c => !c.isdeleted());
    }
}


