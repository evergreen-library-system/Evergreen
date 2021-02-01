import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {of, Observable} from 'rxjs';
import {tap, take, map} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {EventService, EgEvent} from '@eg/core/event.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PoService} from './po.service';
import {LineitemService} from '../lineitem/lineitem.service';
import {CancelDialogComponent} from '../lineitem/cancel-dialog.component';


@Component({
  templateUrl: 'summary.component.html',
  selector: 'eg-acq-po-summary'
})
export class PoSummaryComponent implements OnInit {

    private _poId: number;
    @Input() set poId(id: number) {
        if (id === this._poId) { return; }
        this._poId = id;
        if (this.initDone) { this.load(); }
    }
    get poId(): number { return this._poId; }

    newPoName: string;
    editPoName = false;
    initDone = false;
    ediMessageCount = 0;
    invoiceCount = 0;
    showNotes = false;
    zeroCopyActivate = false;
    canActivate: boolean = null;

    activationBlocks: EgEvent[] = [];
    activationEvent: EgEvent;
    nameEditEnterToggled = false;

    @ViewChild('cancelDialog') cancelDialog: CancelDialogComponent;
    @ViewChild('progressDialog') progressDialog: ProgressDialogComponent;

    constructor(
        private router: Router,
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: ServerStoreService,
        private liService: LineitemService,
        private poService: PoService
    ) {}

    ngOnInit() {
        this.load().then(_ => this.initDone = true);

        // Re-check for activation blocks if the LI service tells us
        // something significant happened.
        this.liService.activateStateChange
        .subscribe(_ => this.setCanActivate());
    }

    po(): IdlObject {
        return this.poService.currentPo;
    }

    load(): Promise<any> {
        if (!this.poId) { return Promise.resolve(); }

        return this.poService.getFleshedPo(this.poId)
        .then(po => {

            // EDI message count
            return this.pcrud.search('acqedim',
                {purchase_order: this.poId}, {}, {idlist: true, atomic: true}
            ).toPromise().then(ids => this.ediMessageCount = ids.length);

        }).then(_ => {

            // Invoice count
            return this.net.request('open-ils.acq',
                'open-ils.acq.invoice.unified_search.atomic',
                this.auth.token(), {acqpo: [{id: this.poId}]},
                null, null, {id_list: true}
            ).toPromise().then(ids => this.invoiceCount = ids.length);

        }).then(_ => this.setCanActivate());
    }

    // Can run via Enter or blur.  If it just ran via Enter, avoid
    // running it again on the blur, which will happen directly after
    // the Enter.
    toggleNameEdit(fromEnter?: boolean) {
        if (fromEnter) {
            this.nameEditEnterToggled = true;
        } else {
            if (this.nameEditEnterToggled) {
                this.nameEditEnterToggled = false;
                return;
            }
        }

        this.editPoName = !this.editPoName;

        if (this.editPoName) {
            this.newPoName = this.po().name();
            setTimeout(() => {
                const node =
                    document.getElementById('pl-name-input') as HTMLInputElement;
                if (node) { node.select(); }
            });

        } else if (this.newPoName && this.newPoName !== this.po().name()) {

            const prevName = this.po().name();
            this.po().name(this.newPoName);
            this.newPoName = null;

            this.pcrud.update(this.po()).subscribe(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    alert(evt);
                    this.po().name(prevName);
                }
            });
        }
    }

    cancelPo() {
        this.cancelDialog.open().subscribe(reason => {
            if (!reason) { return; }

            this.progressDialog.reset();
            this.progressDialog.open();
            this.net.request('open-ils.acq',
                'open-ils.acq.purchase_order.cancel',
                this.auth.token(), this.poId, reason
            ).subscribe(ok => {
                this.progressDialog.close();
                location.href = location.href;
            });
        });
    }

    setCanActivate() {
        this.canActivate = null;
        this.activationBlocks = [];

        if (!(this.po().state().match(/new|pending/))) {
            this.canActivate = false;
            return;
        }

        const options = {
            zero_copy_activate: this.zeroCopyActivate
        };

        this.net.request('open-ils.acq',
            'open-ils.acq.purchase_order.activate.dry_run',
            this.auth.token(), this.poId, null, options

        ).pipe(tap(resp => {

            const evt = this.evt.parse(resp);
            if (evt) { this.activationBlocks.push(evt); }

        })).toPromise().then(_ => {

            if (this.activationBlocks.length === 0) {
                this.canActivate = true;
                return;
            }

            this.canActivate = false;
        });
    }

    activatePo(noAssets?: boolean) {
        this.activationEvent = null;
        this.progressDialog.open();
        this.progressDialog.update({max: this.po().lineitem_count() * 3});

         // Bypass any Vandelay choices and force-load all records.
         // TODO: Add intermediate Vandelay options.
        const vandelay = {
            import_no_match: true,
            queue_name: `ACQ ${new Date().toISOString()}`
        };

        const options = {
            zero_copy_activate: this.zeroCopyActivate,
            no_assets: noAssets
        };

        this.net.request(
            'open-ils.acq',
            'open-ils.acq.purchase_order.activate',
            this.auth.token(), this.poId, vandelay, options
        ).subscribe(resp => {
            const evt = this.evt.parse(resp);

            if (evt) {
                this.progressDialog.close();
                this.activationEvent = evt;
                return;
            }

            if (Number(resp) === 1) {
                this.progressDialog.close();
                // Refresh everything.
                location.href = location.href;

            } else {
                this.progressDialog.update(
                    {value: resp.bibs + resp.li + resp.vqbr});
            }
        });
    }
}


