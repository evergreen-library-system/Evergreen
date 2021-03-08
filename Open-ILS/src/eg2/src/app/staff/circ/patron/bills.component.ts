import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, empty} from 'rxjs';
import {concatMap, tap, takeLast} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
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
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {CreditCardDialogComponent, CreditCardPaymentParams
    } from '@eg/staff/share/circ/credit-card-dialog.component';

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
    paymentAmount: number;
    annotatePayment = false;
    annotation: string;
    entries: BillGridEntry[];
    convertChangeToCredit = false;
    receiptOnPayment = false;
    ccPaymentParams: CreditCardPaymentParams;

    maxPayAmount = 100000;
    warnPayAmount = 1000;

    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('billGrid') private billGrid: GridComponent;
    @ViewChild('annotateDialog') private annotateDialog: PromptDialogComponent;
    @ViewChild('maxPayDialog') private maxPayDialog: AlertDialogComponent;
    @ViewChild('warnPayDialog') private warnPayDialog: ConfirmDialogComponent;
    @ViewChild('creditCardDialog') private creditCardDialog: CreditCardDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private serverStore: ServerStoreService,
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

        this.applySettings().then(_ => this.load());
    }

    applySettings(): Promise<any> {
        return this.serverStore.getItemBatch([
            'ui.circ.billing.amount_warn',
            'ui.circ.billing.amount_limit'
        ]).then(sets => {
            this.maxPayAmount = sets['ui.circ.billing.amount_limit'] || 100000;
            this.warnPayAmount = sets['ui.circ.billing.amount_warn'] || 1000;
        });
    }

    ngAfterViewInit() {
        this.focusPayAmount();
    }

    focusPayAmount() {
        setTimeout(() => {
            const node = document.getElementById('pay-amount') as HTMLInputElement;
            if (node) { node.focus(); node.select(); }
        });
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

            entry.xact.grocery().billing_location(
                this.org.get(entry.xact.grocery().billing_location()));

            entry.title = xact.summary().last_billing_type();
            entry.billingLocation =
                xact.grocery().billing_location().shortname();
            return entry;
        }

        entry.xact.circulation().circ_lib(
            this.org.get(entry.xact.circulation().circ_lib()));

        const circDisplay: CircDisplayInfo =
            this.circ.getDisplayInfo(xact.circulation());

        entry.billingLocation =
            xact.circulation().circ_lib().shortname();

        return Object.assign(entry, circDisplay);
    }

    patron(): IdlObject {
        return this.context.patron;
    }

    selectedPaymentInfo(): {owed: number, billed: number, paid: number} {
        const info = {owed : 0, billed : 0, paid : 0};

        this.billGrid.context.rowSelector.selected().forEach(id => {
            const row = this.billGrid.context.getRowByIndex(id);
            const sum = row.xact.summary();

            info.owed   += Number(sum.balance_owed()) * 100;
            info.billed += Number(sum.total_owed()) * 100;
            info.paid   += Number(sum.total_paid()) * 100;
        });

        info.owed /= 100;
        info.billed /= 100;
        info.paid /= 100;

        return info;
    }

    pendingPaymentInfo(): {payment: number, change: number} {

        const amt = this.paymentAmount || 0;

        if (amt >= this.paidSelected()) {
            const owedSelected = this.owedSelected();
            return {
                payment : this.owedSelected(),
                change : amt - owedSelected
            }
        }

        return {payment : amt, change : 0};
    }

    disablePayment(): boolean {
        if (!this.billGrid) { return true; } // still loading

        return (
            this.paymentAmount === 0 ||
            (this.paymentAmount < 0 && this.paymentType !== 'refund') ||
            this.billGrid.context.rowSelector.selected().length === 0
        );
    }

    refundsAvailable(): number {
        let amount = 0;
        this.gridDataSource.data.forEach(row => {
            const balance = row.xact.summary().balance_owed();
            if (balance < 0) { amount += balance * 100; }

        });

        return -(amount / 100);
    }

    paidSelected(): number {
        return this.selectedPaymentInfo().paid;
    }

    owedSelected(): number {
        return this.selectedPaymentInfo().owed;
    }

    billedSelected(): number {
        return this.selectedPaymentInfo().billed;
    }

    pendingPayment(): number {
        return this.pendingPaymentInfo().payment;
    }

    pendingChange(): number {
        return this.pendingPaymentInfo().change;
    }

    applyPayment() {

        if (this.amountExceedsMax()) { return; }

        this.annotation = '';

        this.verifyPayAmount()
        .then(_ => this.annotate())
        .then(_ => this.addCcArgs())
        .catch(err => console.debug('Payment was canceled:', err));
    }

    amountExceedsMax(): boolean {
        if (this.paymentAmount < this.maxPayAmount) { return false; }
        this.maxPayDialog.open().toPromise().then(_ => this.focusPayAmount());
        return true;
    }

    addCcArgs(): Promise<any> {
        this.ccPaymentParams = {};

        if (this.paymentType !== 'credit_card_payment') {
            return Promise.resolve();
        }

        return this.creditCardDialog.open().toPromise().then(ccArgs => {
            if (ccArgs) {
                this.ccPaymentParams = ccArgs;
            } else {
                return Promise.reject('CC dialog canceled');
            }
        });
    }

    verifyPayAmount(): Promise<any> {
        if (this.paymentAmount < this.warnPayAmount) {
            return Promise.resolve();
        }

        return this.warnPayDialog.open().toPromise().then(confirmed => {
            if (!confirmed) {
                return Promise.reject('Pay amount not confirmed');
            }
        });
    }

    annotate(): Promise<any> {
        if (!this.annotatePayment) { return Promise.resolve(); }

        return this.annotateDialog.open().toPromise()
        .then(value => {
            if (!value) {
                return Promise.reject('No annotation supplied');
            }
            this.annotation = value;
        });
    }
}

