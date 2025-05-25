import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, concatMap, tap} from 'rxjs';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {Pager} from '@eg/share/util/pager';
import {CircService} from '@eg/staff/share/circ/circ.service';
import {PrintService} from '@eg/share/print/print.service';
import {BillingService} from '@eg/staff/share/billing/billing.service';
import {AddBillingDialogComponent} from '@eg/staff/share/billing/billing-dialog.component';
import {DateUtil} from '@eg/share/util/date';

@Component({
    templateUrl: 'billing-history.component.html',
    selector: 'eg-patron-billing-history'
})
export class BillingHistoryComponent implements OnInit {

    @Input() patronId: number;
    @Input() tab: string;

    xactsDataSource: GridDataSource = new GridDataSource();
    paymentsDataSource: GridDataSource = new GridDataSource();

    xactsTextGenerator: GridCellTextGenerator;
    paymentsTextGenerator: GridCellTextGenerator;

    xactsStart: string;
    xactsEnd: string;

    paymentsStart: string;
    paymentsEnd: string;

    @ViewChild('xactsGrid') private xactsGrid: GridComponent;
    @ViewChild('paymentsGrid') private paymentsGrid: GridComponent;
    @ViewChild('billingDialog') private billingDialog: AddBillingDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private org: OrgService,
        private evt: EventService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private idl: IdlService,
        private circ: CircService,
        private billing: BillingService,
        private printer: PrintService,
        private flatData: GridFlatDataService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.tab = params.get('billingHistoryTab') || 'transactions';
        });


        const start = new Date();
        const end = new Date();
        start.setFullYear(start.getFullYear() - 1);
        end.setDate(end.getDate() + 1);

        this.xactsStart = this.paymentsStart = DateUtil.localYmdFromDate(start);
        this.xactsEnd = this.paymentsEnd = DateUtil.localYmdFromDate(end);

        this.xactsDataSource.getRows = (pager: Pager, sort: any[]) => {

            if (sort.length === 0) {
                sort = [{name: 'xact_start', dir: 'DESC'}];
            }

            const query: any = {
                usr: this.patronId,
                xact_start: {between: [this.xactsStart, this.xactsEnd]},
                '-or': [
                    {balance_owed: {'<>': 0}},
                    {last_payment_ts: {'<>': null}}
                ]
            };

            return this.flatData.getRows(
                this.xactsGrid.context, query, pager, sort);
        };

        this.paymentsDataSource.getRows = (pager: Pager, sort: any[]) => {
            const query: any = {
                'xact.usr': this.patronId,
                payment_ts: {between: [this.paymentsStart, this.paymentsEnd]},
            };

            if (sort.length === 0) {
                sort = [{name: 'payment_ts', dir: 'DESC'}];
            }

            return this.flatData.getRows(
                this.paymentsGrid.context, query, pager, sort);
        };
    }

    dateChange(which: string, d: Date) {

        if (which.match(/End/)) {
            // Add a day to the end date so the DB query includes all of
            // the selected date.
            d.setDate(d.getDate() + 1);
        }

        this[which] = DateUtil.localYmdFromDate(d);

        if (which.match(/xacts/)) {
            this.xactsGrid.reload();
        } else {
            this.paymentsGrid.reload();
        }
    }

    beforeTabChange(evt: NgbNavChangeEvent) {
        // tab will change with route navigation.
        evt.preventDefault();
        this.router.navigate([
            `/staff/circ/patron/${this.patronId}/bills/history/${evt.nextId}`]);
    }


    showStatement(row: any | any[], forPayment?: boolean) {
        row = [].concat(row)[0];
        const id = forPayment ? row['xact.id'] : row.id;
        this.router.navigate(['/staff/circ/patron',
            this.patronId, 'bills', id, 'statement']);
    }

    addBillingForXact(rows: any[]) {
        if (rows.length === 0) { return; }
        const xactIds = rows.map(r => r.id);

        this.billingDialog.newXact = false;
        let changesApplied = false;

        from(xactIds)
            .pipe(concatMap(id => {
                this.billingDialog.xactId = id;
                return this.billingDialog.open();
            }))
            .pipe(tap(data => {
                if (data) {
                    changesApplied = true;
                }
            }))
            .subscribe({ complete: () => {
                if (changesApplied) {
                    this.xactsGrid.reload();
                }
            } });
    }

    printBills(rows: any) {
        if (rows.length === 0) { return; }

        this.printer.print({
            templateName: 'bills_historical',
            contextData: {xacts: rows},
            printContext: 'default'
        });
    }

    selectedPaymentsInfo(): {paid: number} {
        const info = {paid: 0};
        if (!this.paymentsGrid) { return info; }

        this.paymentsGrid.context.rowSelector.selected().forEach(id => {
            const row = this.paymentsGrid.context.getRowByIndex(id);
            if (!row) { return; }
            info.paid += Number(row.amount) * 100;
        });

        info.paid /= 100;
        return info;
    }

    selectedXactsInfo(): {owed: number, billed: number, paid: number} {
        const info = {owed : 0, billed : 0, paid : 0};

        if (!this.xactsGrid) { return info; } // page loading

        this.xactsGrid.context.rowSelector.selected().forEach(id => {
            const row = this.xactsGrid.context.getRowByIndex(id);

            if (!row) { return; } // Called mid-reload

            info.owed   += Number(row.balance_owed) * 100;
            info.billed += Number(row.total_owed) * 100;
            info.paid   += Number(row.total_paid) * 100;
        });

        info.owed /= 100;
        info.billed /= 100;
        info.paid /= 100;

        return info;
    }
}


