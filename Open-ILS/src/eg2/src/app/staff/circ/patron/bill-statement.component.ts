import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, empty, range} from 'rxjs';
import {concatMap, tap, takeLast} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
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
import {Pager} from '@eg/share/util/pager';
import {CircService, CircDisplayInfo} from '@eg/staff/share/circ/circ.service';
import {PrintService} from '@eg/share/print/print.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {CreditCardDialogComponent
    } from '@eg/staff/share/billing/credit-card-dialog.component';
import {BillingService, CreditCardPaymentParams} from '@eg/staff/share/billing/billing.service';
import {AddBillingDialogComponent} from '@eg/staff/share/billing/billing-dialog.component';
import {AudioService} from '@eg/share/util/audio.service';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
  templateUrl: 'bill-statement.component.html',
  selector: 'eg-patron-bill-statement'
})
export class BillStatementComponent implements OnInit {

    @Input() patronId: number;
    @Input() xactId: number;
    statement: any;
    statementTab = 'statement';
    billingDataSource: GridDataSource = new GridDataSource();
    paymentDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    noteTargets: string;
    voidTargets: string;
    voidAmount: number;

    @ViewChild('billingGrid') private billingGrid: GridComponent;
    @ViewChild('noteDialog') private noteDialog: PromptDialogComponent;
    @ViewChild('voidBillsDialog') private voidBillsDialog: ConfirmDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private audio: AudioService,
        private toast: ToastService,
        private org: OrgService,
        private evt: EventService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private printer: PrintService,
        private serverStore: ServerStoreService,
        private circ: CircService,
        private billing: BillingService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        this.cellTextGenerator = {
        };

        this.billingDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                orderBy.mb = sort[0].name + ' ' + sort[0].dir;
            }
            return this.pcrud.search(
                'mb', {xact: this.xactId}, {order_by: orderBy});
        };

        this.paymentDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                orderBy.mp = sort[0].name + ' ' + sort[0].dir;
            }
            return this.pcrud.search(
                'mp', {xact: this.xactId}, {order_by: orderBy});
        };


        this.net.request(
            'open-ils.circ',
            'open-ils.circ.money.statement.retrieve',
            this.auth.token(), this.xactId
        ).subscribe(s => this.statement = s);
    }

    openNoteDialog(rows: IdlObject[]) {
        if (rows.length === 0) { return; }

        const notes = rows.map(r => r.note() || '').join(',');
        const ids = rows.map(r => r.id());
        this.noteTargets = ids.join(',');
        this.noteDialog.promptValue = notes;

        this.noteDialog.open().subscribe(value => {
            if (value === notes) { return; }

            let method = 'open-ils.circ.money.billing.note.edit';
            if (rows[0].classname === 'mp') {
                method = 'open-ils.circ.money.payment.note.edit';
            }

            this.net.requestWithParamList(
                'open-ils.circ', method, [this.auth.token()].concat(ids))
            .toPromise().then(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    console.error(evt);
                } else {
                    rows.forEach(r => r.note(value));
                }
            });
        });
    }

    openVoidDialog(rows: IdlObject[]) {
        rows = rows.filter(r => r.voided() === 'f');

        let amount = 0;
        rows.forEach(billing => amount += billing.amount() * 100);

        const ids = rows.map(r => r.id());
        this.voidAmount = amount / 100;
        this.voidTargets = ids.join(',');

        this.voidBillsDialog.open().subscribe(confirmed => {
            if (!confirmed) { return; }

            this.net.requestWithParamList(
                'open-ils.circ',
                'open-ils.circ.money.billing.void',
                [this.auth.token()].concat(ids)).toPromise()
            .then(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    console.error(evt);
                } else {
                    this.context.refreshPatron();
                    this.billingGrid.reload();
                }
            });
        });
    }
}

