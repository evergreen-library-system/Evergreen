import {Component, OnInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {EventService} from '@eg/core/event.service';
import {PoService} from './po.service';
import {LineitemService} from '../lineitem/lineitem.service';

const VALID_PRE_PO_LI_STATES = [
    'new',
    'selector-ready',
    'order-ready',
    'approved'
];

@Component({
    templateUrl: 'create.component.html',
    selector: 'eg-acq-po-create'
})
export class PoCreateComponent implements OnInit {

    initDone = false;
    lineitems: number[] = [];
    origLiCount = 0;
    poName: string;
    orderAgency: number;
    provider: ComboboxEntry;
    prepaymentRequired = false;
    createAssets = false;
    dupeResults = {
        dupeFound: false,
        dupePoId: -1
    };

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
        this.poService.currentPo = null;

        this.route.queryParamMap.subscribe((params: ParamMap) => {
            this.lineitems = params.getAll('li').map(id => Number(id));
            this.origLiCount = this.lineitems.length;
        });

        this.load();
    }

    load() {
        this.dupeResults.dupeFound = false;
        this.dupeResults.dupePoId = -1;
        if (this.origLiCount > 0) {
            const fleshed_lis: IdlObject[] = [];
            this.liService.getFleshedLineitems(this.lineitems, { fromCache: false }).subscribe(
                { next: liStruct => {
                    fleshed_lis.push(liStruct.lineitem);
                }, error: (err: unknown) => { }, complete: () => {
                    this.lineitems = fleshed_lis.filter(li => VALID_PRE_PO_LI_STATES.includes(li.state()))
                        .map(li => li.id());
                    this.initDone = true;
                } }
            );
        } else {
            this.initDone = true;
        }
    }

    orgChange(org: IdlObject) {
        this.orderAgency = org ? org.id() : null;
        this.checkDuplicatePoName();
    }

    canCreate(): boolean {
        return (Boolean(this.orderAgency) && Boolean(this.provider) &&
                !this.dupeResults.dupeFound);
    }

    checkDuplicatePoName() {
        this.poService.checkDuplicatePoName(this.orderAgency, this.poName, this.dupeResults);
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

        this.net.request('open-ils.acq',
            'open-ils.acq.purchase_order.create',
            this.auth.token(), po, args
        ).toPromise().then(resp => {
            if (resp && resp.purchase_order) {
                if (this.createAssets) {
                    this.router.navigate(
                        ['/staff/acq/po/' + resp.purchase_order.id() + '/create-assets']);
                } else {
                    this.router.navigate(
                        ['/staff/acq/po/' + resp.purchase_order.id()]);
                }
            }
        });
    }
}


