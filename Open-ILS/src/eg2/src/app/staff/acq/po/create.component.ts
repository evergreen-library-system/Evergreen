import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
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
  templateUrl: 'create.component.html',
  selector: 'eg-acq-po-create'
})
export class PoCreateComponent implements OnInit {

    initDone = false;
    lineitems: number[] = [];
    poName: string;
    orderAgency: number;
    provider: ComboboxEntry;
    prepaymentRequired = false;
    createAssets = false;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
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
        this.route.queryParamMap.subscribe((params: ParamMap) => {
            this.lineitems = params.getAll('li').map(id => Number(id));
        });

        this.load().then(_ => this.initDone = true);
    }

    load(): Promise<any> {
        return Promise.resolve();
    }

    orgChange(org: IdlObject) {
        this.orderAgency = org ? org.id() : null;
    }

    canCreate(): boolean {
        return (Boolean(this.orderAgency) && Boolean(this.provider));
    }

    create() {

        const po = this.idl.create('acqpo');
        po.ordering_agency(this.orderAgency);
        po.provider(this.provider.id);
        po.name(this.poName || null);
        po.prepayment_required(this.prepaymentRequired ? 't' : 'f');

        const args: any = {};
        if (this.lineitems.length > 0) {
            args.lineitems = this.lineitems;
        }

        if (this.createAssets) {
            // This version simply creates all records sans Vandelay merging, etc.
            // TODO: go to asset creator.
            args.vandelay = {
                import_no_match: true,
                queue_name: `ACQ ${new Date().toISOString()}`
            };
        }

        this.net.request('open-ils.acq',
            'open-ils.acq.purchase_order.create',
            this.auth.token(), po, args
        ).toPromise().then(resp => {
            if (resp && resp.purchase_order) {
                this.router.navigate(
                    ['/staff/acq/po/' + resp.purchase_order.id()]);
            }
        });
    }
}


