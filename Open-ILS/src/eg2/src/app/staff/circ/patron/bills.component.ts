import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, empty} from 'rxjs';
import {concatMap, tap} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {CircService, CircDisplayInfo} from '@eg/staff/share/circ/circ.service';

interface BillGridEntry extends CircDisplayInfo {
    xact: IdlObject // mbt
    billingLocation?: string;
    paymentPending?: number;
}

const XACT_FLESH_DEPTH = 5;
const XACT_FLESH_FIELDS = {
  mbt: ['summary', 'circulation', 'grocery'],
  circ: ['target_copy', 'workstation', 'checkin_workstation', 'circ_lib'],
  acp:  [
    'call_number',
    'holds_count',
    'status',
    'circ_lib',
    'location',
    'floating',
    'age_protect',
    'parts'
  ],
  acpm: ['part'],
  acn:  ['record', 'owning_lib', 'prefix', 'suffix'],
  bre:  ['wide_display_entry']
};


@Component({
  templateUrl: 'bills.component.html',
  selector: 'eg-patron-bills',
  styleUrls: ['bills.component.css']
})
export class BillsComponent implements OnInit, AfterViewInit {

    @Input() patronId: number;
    summary: IdlObject;
    sessionVoided = 0;
    paymentType = 'cash_payment';
    checkNumber: string;
    annotatePayment = false;
    entries: BillGridEntry[];

    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('billGrid') private billGrid: GridComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: ServerStoreService,
        private circ: CircService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        this.cellTextGenerator = {
            title: row => row.title,
            copy_barcode: row => row.copy ? row.copy.barcode() : '',
            call_number: row => row.volume ? row.volume.label() : ''
        };

        // The grid never fetches data directly, it only serves what
        // we have manually retrieved.
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            if (!this.entries) { return empty(); }

            const page =
                this.entries.slice(pager.offset, pager.offset + pager.limit)
                .filter(entry => entry !== undefined);

            return from(page);
        };

        this.load();
    }

    ngAfterViewInit() {
        const node = document.getElementById('pay-amount');
        if (node) { node.focus(); }
    }

    load() {

        const xactIds = [];


        // TODO: run this in a single pcrud transaction

        this.pcrud.retrieve('mous', this.patronId, {}, {authoritative : true})
        .pipe(tap(sum => this.summary = sum))
        .pipe(concatMap(_ => {
            return this.pcrud.search('mbts',
                {usr: this.patronId, balance_owed: {'<>' : 0}},
                {select: {mbts: ['id']}}, {authoritative : true}
            ).pipe(tap(summary => xactIds.push(summary.id())));
        }))
        .pipe(concatMap(_ => {
            this.entries = [];
            return this.pcrud.search('mbt', {id: xactIds}, {
                flesh: XACT_FLESH_DEPTH,
                flesh_fields: XACT_FLESH_FIELDS,
                order_by: {mbts : ['xact_start']},
                select: {bre : ['id']}
                }, {authoritative : true}
            ).pipe(tap(xact => this.entries.push(this.formatForDisplay(xact))));
        }))
        .subscribe(null, null, () => this.billGrid.reload());
    }

    formatForDisplay(xact: IdlObject): BillGridEntry {

        const entry: BillGridEntry = {
            xact: xact,
            paymentPending: 0
        };

        if (xact.summary().xact_type() !== 'circulation') {
            entry.title = xact.summary().last_billing_type();
            entry.billingLocation =
                xact.grocery().billing_location().shortname();
            return entry;
        }

        const circDisplay: CircDisplayInfo =
            this.circ.getDisplayInfo(xact.circulation());

        entry.billingLocation =
            xact.circulation().circ_lib().shortname();

        return Object.assign(entry, circDisplay);
    }

    patron(): IdlObject {
        return this.context.patron;
    }

    // TODO
    refundsAvailable(): number {
        return 0;
    }

    // TODO
    paidSelected(): number {
        return 0;
    }

    // TODO
    owedSelected(): number {
        return 0;
    }

    // TODO
    billedSelected(): number {
        return 0;
    }

    pendingPayment(): number {
        return 0;
    }

    pendingChange(): number {
        return 0;
    }

}

