import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, empty, range} from 'rxjs';
import {concatMap, tap, takeLast} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService, PcrudContext} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService, BillGridEntry} from './patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {Pager} from '@eg/share/util/pager';
import {CircService, CircDisplayInfo} from '@eg/staff/share/circ/circ.service';
import {PrintService} from '@eg/share/print/print.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {BillingService} from '@eg/staff/share/billing/billing.service';
import {AddBillingDialogComponent} from '@eg/staff/share/billing/billing-dialog.component';
import {AudioService} from '@eg/share/util/audio.service';
import {ToastService} from '@eg/share/toast/toast.service';

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

        this.xactsDataSource.getRows = (pager: Pager, sort: any[]) => {

            const query: any = {
               usr: this.patronId,
               xact_start: {between: ['2020-04-16', 'now']},
               '-or': [
                    {'summary.balance_owed': {'<>': 0}},
                    {'summary.last_payment_ts': {'<>': null}}
               ]
            };

            return this.flatData.getRows(
                this.xactsGrid.context, query, pager, sort);
        };

        /*
        this.paymentsDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                orderBy.mp = sort[0].name + ' ' + sort[0].dir;
            }
            return this.pcrud.search(
                'mp', {xact: this.xactId}, {order_by: orderBy});
        };
        */
    }

    showStatement(row: BillGridEntry) {
        this.router.navigate(['/staff/circ/patron',
            this.patronId, 'bills', row.xact.id(), 'statement']);
    }

    addBillingForXact(rows: BillGridEntry[]) {
        if (rows.length === 0) { return; }
        const xactIds = rows.map(r => r.xact.id());

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
        .subscribe(null, null, () => {
            if (changesApplied) {
                this.xactsGrid.reload();
            }
        });
    }

    printBills(rows: BillGridEntry[]) {
        if (rows.length === 0) { return; }

        this.printer.print({
            templateName: 'bills_historical',
            contextData: {xacts: rows.map(r => r.xact)},
            printContext: 'default'
        });
    }
}


