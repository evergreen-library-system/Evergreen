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
import {PatronContextService} from './patron.service';
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
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';

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
    paymentNote: string;
    convertChangeToCredit = false;
    receiptOnPayment = false;
    applyingPayment = false;
    numReceipts = 1;
    ccPaymentParams: CreditCardPaymentParams;
    disableAutoPrint = false;

    maxPayAmount = 100000;
    warnPayAmount = 1000;
    voidAmount = 0;
    refunding = false;

    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('billGrid') private billGrid: GridComponent;
    @ViewChild('annotateDialog') private annotateDialog: PromptDialogComponent;
    @ViewChild('maxPayDialog') private maxPayDialog: AlertDialogComponent;
    @ViewChild('warnPayDialog') private warnPayDialog: ConfirmDialogComponent;
    @ViewChild('voidBillsDialog') private voidBillsDialog: ConfirmDialogComponent;
    @ViewChild('refundDialog') private refundDialog: ConfirmDialogComponent;
    @ViewChild('adjustToZeroDialog') private adjustToZeroDialog: ConfirmDialogComponent;
    @ViewChild('creditCardDialog') private creditCardDialog: CreditCardDialogComponent;
    @ViewChild('billingDialog') private billingDialog: AddBillingDialogComponent;

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
        private idl: IdlService,
        private printer: PrintService,
        private serverStore: ServerStoreService,
        private circ: CircService,
        private billing: BillingService,
        private flatData: GridFlatDataService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        this.cellTextGenerator = {
            title: row => row.title,
            copy_barcode: row => row.copy_barcode,
            call_number: row => row.call_number_label
        };

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {

            const query: any = {
               usr: this.patronId,
               xact_finish: null,
               'summary.balance_owed' : {'<>' : 0}
            };

            return this.flatData.getRows(
                this.billGrid.context, query, pager, sort)
            .pipe(tap(row => {
                row.paymentPending = 0;
            }));
        };

        this.pcrud.retrieve('mowbus', this.patronId).toPromise()
        // Summary will be null for users with no billing history.
        .then(summary => this.summary = summary || this.idl.create('mowbus'))
        .then(_ => this.loadSettings());
    }

    loadSettings(): Promise<any> {
        return this.serverStore.getItemBatch([
            'ui.circ.billing.amount_warn',
            'ui.circ.billing.amount_limit',
            'circ.staff_client.do_not_auto_attempt_print',
            'circ.bills.receiptonpay',
            'eg.circ.bills.annotatepayment'

        ]).then(sets => {
            this.maxPayAmount = sets['ui.circ.billing.amount_limit'] || 100000;
            this.warnPayAmount = sets['ui.circ.billing.amount_warn'] || 1000;
            this.receiptOnPayment = sets['circ.bills.receiptonpay'];
            this.annotatePayment = sets['eg.circ.bills.annotatepayment'];

            const noPrint = sets['circ.staff_client.do_not_auto_attempt_print'];
            if (noPrint && noPrint.includes('Bill Pay')) {
                this.disableAutoPrint = true;
            }
        });
    }

    applySetting(name: string, value: any) {
        this.serverStore.setItem(name, value);
    }

    ngAfterViewInit() {
        // Recaclulate the amount owed per selected transaction as the
        // grid rows selections change.
        this.billGrid.context.rowSelector.selectionChange
        .subscribe(_ => this.updatePendingColumn());

        this.focusPayAmount();
    }

    focusPayAmount() {
        setTimeout(() => {
            const node = document.getElementById('pay-amount') as HTMLInputElement;
            if (node) { node.focus(); node.select(); }
        });
    }

    patron(): IdlObject {
        return this.context.summary ? this.context.summary.patron : null;
    }

    selectedPaymentInfo(): {owed: number, billed: number, paid: number} {
        const info = {owed : 0, billed : 0, paid : 0};

        if (!this.billGrid) { return info; } // page loading

        this.billGrid.context.rowSelector.selected().forEach(id => {
            const row = this.billGrid.context.getRowByIndex(id);

            if (!row) { return; } // Called mid-reload

            info.owed   += Number(row['summary.balance_owed']) * 100;
            info.billed += Number(row['summary.total_owed']) * 100;
            info.paid   += Number(row['summary.total_paid']) * 100;
        });

        info.owed /= 100;
        info.billed /= 100;
        info.paid /= 100;

        return info;
    }


    pendingPaymentInfo(): {payment: number, change: number} {

        const amt = this.paymentAmount || 0;
        const owedSelected = this.owedSelected();

        if (amt >= owedSelected) {
            return {
                payment : owedSelected,
                change : amt - owedSelected
            };
        }

        return {payment : amt, change : 0};
    }

    disablePayment(): boolean {
        if (!this.billGrid) { return true; } // still loading

        return (
            this.applyingPayment ||
            !this.pendingPayment() ||
            this.paymentAmount === 0 ||
            (this.paymentAmount < 0 && !this.refunding) ||
            this.billGrid.context.rowSelector.selected().length === 0
        );
    }

    refundsAvailable(): number {
        let amount = 0;
        this.gridDataSource.data.forEach(row => {
            const balance = row['summary.balance_owed'];
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

        this.applyingPayment = true;
        this.paymentNote = '';
        this.ccPaymentParams = {};
        const payments = this.compilePayments();

        this.verifyPayAmount()
        .then(_ => this.annotate())
        .then(_ => this.getCcParams())
        .then(_ => {
            return this.billing.applyPayment(
                this.patronId,
                this.patron().last_xact_id(),
                this.paymentType,
                payments,
                this.paymentNote,
                this.checkNumber,
                this.ccPaymentParams,
                this.convertChangeToCredit
            );
        })
        .then(paymentIds => this.handlePayReceipt(payments, paymentIds))

        // refresh affected xact IDs
        .then(_ => this.billGrid.reload())

        .then(_ => {
            this.paymentAmount = null;
            this.focusPayAmount();
        })

        .catch(msg => console.debug('Payment Canceled:', msg))
        .finally(() => {
            this.applyingPayment = false;
            this.refunding = false;
        });
    }

    compilePayments(): Array<Array<number>> { // [ [xactId, payAmount], ... ]
        const payments = [];
        this.gridDataSource.data.forEach(row => {
            if (row.paymentPending) {
                payments.push([row.id, row.paymentPending]);
            }
        });
        return payments;
    }

    amountExceedsMax(): boolean {
        if (this.paymentAmount < this.maxPayAmount) { return false; }
        this.maxPayDialog.open().toPromise().then(_ => this.focusPayAmount());
        return true;
    }

    // Credit card info
    getCcParams(): Promise<any> {
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
                // TODO: there is no way in PromptDialog to
                // differentiate between canceling the dialog and
                // submitting the dialog with no value.  In this case,
                // if the dialog is submitted with no value, we may want
                // to leave the dialog open so a value can be applied.
                return Promise.reject('No annotation supplied');
            }
            this.paymentNote = value;
        });
    }

    updatePendingColumn() {

        // Reset...
        this.gridDataSource.data.forEach(row => row.paymentPending = 0);

        let amount = this.pendingPayment();
        let done = false;

        this.billGrid.context.rowSelector.selected().forEach(index => {
            if (done) { return; }

            const row = this.billGrid.context.getRowByIndex(index);
            const owed = Number(row['summary.balance_owed']);

            if (amount > owed) {
                // Pending payment amount exceeds balance of this
                // row.  Pay the entire amount
                row.paymentPending = owed;
                amount -= owed;

            } else {
                // balance owed on the current item matches or exceeds
                // the pending payment.  Apply the full remainder of
                // the payment to this item... and we're done.
                //
                // Limit to two decimal places to avoid floating point
                // issues and cast back to number to match data type.
                row.paymentPending = Number(amount.toFixed(2));
                done = true;
            }
        });
    }

    printBills(rows: any[]) {
        if (rows.length === 0) { return; }

        this.printer.print({
            templateName: 'bills_current',
            contextData: {xacts: rows},
            printContext: 'default'
        });
    }

    handlePayReceipt(payments: Array<Array<number>>, paymentIds: number[]): Promise<any> {

        if (this.disableAutoPrint || !this.receiptOnPayment) {
            return Promise.resolve();
        }

        const pending = this.pendingPayment();
        const prevBalance = this.context.summary.stats.fines.balance_owed;
        const newBalance = (prevBalance * 100 - pending * 100) / 100;

        const context = {
            payments: [],
            previous_balance: prevBalance,
            new_balance: newBalance,
            payment_type: this.paymentType,
            payment_total: this.paymentAmount,
            payment_applied: pending,
            amount_voided: this.sessionVoided,
            change_given: this.pendingChange(),
            payment_note: this.paymentNote
        };

        payments.forEach(payment => {

            const entry =
                this.gridDataSource.data.filter(e => e.xact.id() === payment[0])[0];

            context.payments.push({
                amount: payment[1],
                xact: entry,
                title: entry.title,
                copy_barcode: entry.copy_barcode
            });
        });

        // The print service protects against multiple print attempts
        // firing at once, so it's OK to fire these in quick succession.
        range(1, this.numReceipts).subscribe(_ => {
            this.printer.print({
                templateName: 'bills_payment',
                contextData: context,
                printContext: 'receipt'
            });
        });
    }

    selectRefunds() {
        this.billGrid.context.rowSelector.clear();
        this.gridDataSource.data.forEach(row => {
            if (row['summary.balance_owed'] < 0) {
                this.billGrid.context.toggleSelectOneRow(row.id);
            }
        });
    }

    addBilling() {
        this.billingDialog.newXact = true;
        this.billingDialog.open().subscribe(data => {
            if (data) {
                this.billGrid.reload();
            }
        });
    }

    addBillingForXact(rows: any[]) {
        if (rows.length === 0) { return; }
        const xactIds = rows.map(r => r.id);

        this.billingDialog.newXact = false;
        const xactsChanged = [];

        from(xactIds)
        .pipe(concatMap(id => {
            this.billingDialog.xactId = id;
            return this.billingDialog.open();
        }))
        .pipe(tap(data => {
            if (data) {
                xactsChanged.push(data.xactId);
            }
        }))
        .subscribe(null, null, () => {
            if (xactsChanged.length > 0) {
                this.billGrid.reload();
            }
        });
    }

    voidBillings(rows: any[]) {
        if (rows.length === 0) { return; }

        const xactIds = rows.map(r => r.id);
        const billIds = [];
        let cents = 0;

        from(xactIds)
        // Grab the billings
        .pipe(concatMap(xactId => {
            return this.pcrud.search('mb', {xact: xactId}, {}, {authoritative: true})
            .pipe(tap(billing => {
                if (billing.voided() === 'f') {
                    cents += billing.amount() * 100;
                    billIds.push(billing.id());
                }
            }));
        }))
        // Confirm the void action
        .pipe(concatMap(_ => {
            this.voidAmount = cents / 100;
            return this.voidBillsDialog.open();
        }))
        // Do the void
        .pipe(concatMap(confirmed => {
            if (!confirmed) { return empty(); }

            return this.net.requestWithParamList(
                'open-ils.circ',
                'open-ils.circ.money.billing.void',
                [this.auth.token()].concat(billIds) // positional params
            );
        }))
        // Clean up and refresh data
        .subscribe(resp => {
            if (!resp || this.reportError(resp)) { return; }

            this.sessionVoided = (this.sessionVoided * 100 + cents) / 100;
            this.voidAmount = 0;
            this.billGrid.reload();
        });
    }

    adjustToZero(rows: any[]) {
        if (rows.length === 0) { return; }
        const xactIds = rows.map(r => r.id);

        this.audio.play('warning.circ.adjust_to_zero_confirmation');

        this.adjustToZeroDialog.open().subscribe(confirmed => {
            if (!confirmed) { return; }

            this.net.request(
                'open-ils.circ',
                'open-ils.circ.money.billable_xact.adjust_to_zero',
                this.auth.token(), xactIds
            ).subscribe(resp => {
                if (!this.reportError(resp)) { this.billGrid.reload(); }
            });
        });
    }

    // Returns true if the value was an (error) event
    reportError(value: any): boolean {
        const evt = this.evt.parse(value);
        if (evt) {
            console.error(evt + '');
            console.error(evt);
            this.toast.danger(evt + '');
            return true;
        }
        return false;
    }

    // This is functionally equivalent to selecting a neg. transaction
    // then clicking Apply Payment -- this just adds a speed bump (ditto
    // the XUL client).
    refund(rows: any[]) {
        if (rows.length === 0) { return; }
        const xactIds = rows.map(r => r.id);

        this.refundDialog.open().subscribe(confirmed => {
            if (!confirmed) { return; }
            this.refunding = true; // clearen in applyPayment()
            this.paymentAmount = null;
        });
    }

    showStatement(row: any) {
        this.router.navigate(['/staff/circ/patron',
            this.patronId, 'bills', row.id, 'statement']);
    }
}

