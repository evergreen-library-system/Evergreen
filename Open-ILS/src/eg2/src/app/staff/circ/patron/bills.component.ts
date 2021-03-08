import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, empty} from 'rxjs';
import {concatMap, tap, takeLast} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService, PcrudContext} from '@eg/core/pcrud.service';
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
    payAmount: number;
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

        this.summary = null;
        this.entries = [];
        this.gridDataSource.requestingData = true;

        this.net.request('open-ils.actor',
            'open-ils.actor.user.transactions.for_billing',
            this.auth.token(), this.patronId
        ).subscribe(
            resp => {
                if (!this.summary) { // 1st response is summary
                    this.summary = resp;
                } else {
                    this.entries.push(this.formatForDisplay(resp));
                }
            },
            null,
            () => {
                this.gridDataSource.requestingData = false;
                this.billGrid.reload();
            }
        );
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

    disablePayment(): boolean {
        if (!this.billGrid) { return true; } // still loading

        // TODO: pay amount can be zero when refunding
        return (
            this.payAmount <= 0 ||
            this.billGrid.context.rowSelector.selected().length === 0
        );
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

