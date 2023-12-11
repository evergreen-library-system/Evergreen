import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {from, empty, range} from 'rxjs';
import {concatMap, tap} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator, GridRowFlairEntry} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {CircService} from '@eg/staff/share/circ/circ.service';
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
import {WorkLogService} from '@eg/staff/share/worklog/worklog.service';

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

    // eslint-disable-next-line no-magic-numbers
    maxPayAmount = 100000;
    warnPayAmount = 1000;
    voidAmount = 0;
    refunding = false;

    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    rowClassCallback: (row: any) => string;
    rowFlairCallback: (row: any) => GridRowFlairEntry;
    cellClassCallback: (row: any, col: GridColumn) => string;

    nowTime: number = new Date().getTime();

    @ViewChild('billGrid') private billGrid: GridComponent;
    @ViewChild('annotateDialog') private annotateDialog: PromptDialogComponent;
    @ViewChild('maxPayDialog') private maxPayDialog: AlertDialogComponent;
    @ViewChild('errorDialog') private errorDialog: AlertDialogComponent;
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
        private worklog: WorkLogService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        this.cellClassCallback = (row: any, col: GridColumn): string => {
            if (col.name === 'paymentPending') {
                const val = this.billGrid.context.getRowColumnBareValue(row, col);
                if (val < 0) {
                    return 'bg-warning p-1';
                }
            }
            return '';
        };

        this.cellTextGenerator = {
            title: row => row.title,
            copy_barcode: row => row.copy_barcode,
            call_number: row => row.call_number_label
        };

        this.rowClassCallback = (row: any): string => {
            if (row['circulation.stop_fines'] === 'LOST') {
                return 'lost-row';
            } else if (row['circulation.stop_fines'] === 'LONGOVERDUE') {
                return 'longoverdue-row';
            } else if (this.circIsOverdue(row)) {
                return 'less-intense-alert';
            }
            return '';
        };

        this.rowFlairCallback = (row: any): GridRowFlairEntry => {
            if (row['circulation.stop_fines'] === 'LOST') {
                return {icon: 'help', title: 'Status: Lost'};
            } else if (row['circulation.stop_fines'] === 'LONGOVERDUE') {
                return {icon: 'priority-high', title: 'Status: Long Overdue'};
            } else if (this.circIsOverdue(row)) {
                return {icon: 'schedule', title: 'Status: Overdue'};
            }
        };

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {

            const query: any = {
                usr: this.patronId,
                xact_finish: null,
                balance_owed: {'<>' : 0}
            };

            return this.flatData.getRows(
                this.billGrid.context, query, pager, sort)
                .pipe(tap(row => {
                    row.paymentPending = 0;
                    row.billingLocation =
                    row['grocery.billing_location.shortname'] ||
                    row['circulation.circ_lib.shortname'];
                }));
        };

        this.pcrud.retrieve('mowbus', this.patronId).toPromise()
        // Summary will be null for users with no billing history.
            .then(summary => this.summary = summary || this.idl.create('mowbus'))
            .then(_ => this.loadSettings());
    }

    circIsOverdue(row: any): boolean {
        const due = row['circulation.due_date'];
        if (due && !row['circulation.checkin_time']) {
            const stopFines = row['circulation.stop_fines'] || '';
            if (stopFines.match(/LOST|CLAIMSRETURNED|CLAIMSNEVERCHECKEDOUT/)) {
                return false;
            }

            return (Date.parse(due) < this.nowTime);
        }
    }

    loadSettings(): Promise<any> {
        return this.serverStore.getItemBatch([
            'ui.circ.billing.amount_warn',
            'ui.circ.billing.amount_limit',
            'circ.staff_client.do_not_auto_attempt_print',
            'circ.bills.receiptonpay',
            'eg.circ.bills.annotatepayment'

        ]).then(sets => {
            // eslint-disable-next-line no-magic-numbers
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
            .subscribe(_ => {
                this.refunding = false;
                this.updatePendingColumn();
            });

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

            info.owed   += Number(row.balance_owed) * 100;
            info.billed += Number(row.total_owed) * 100;
            info.paid   += Number(row.total_paid) * 100;
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
            const balance = row.balance_owed;
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
                    this.convertChangeToCredit ? this.pendingChange() : null
                );
            })
            .then(resp => {
                this.worklog.record({
                    user: this.patron().family_name(),
                    patron_id: this.patron().id(),
                    amount: this.pendingPayment(),
                    action: 'paid_bill'
                });
                this.patron().last_xact_id(resp.last_xact_id);
                return this.handlePayReceipt(payments, resp.payments);
            })

            .then(_ => this.context.refreshPatron())

        // refresh affected xact IDs
            .then(_ => this.billGrid.reload())

            .then(_ => {
                this.paymentAmount = null;
                this.focusPayAmount();
            })

            .catch(msg => {
                this.reportError(msg);
                console.debug('Payment Canceled or Failed:', msg);
            })
            .finally(() => {
                this.applyingPayment = false;
                this.refunding = false;
            });
    }

    compilePayments(): Array<Array<number>> { // [ [xactId, payAmount], ... ]
        const payments = [];
        this.gridDataSource.data.forEach(row => {
            if (row.paymentPending) {
                // NOTE passing the pending payment amount as a string
                // instead of a number bypasses some funky rounding
                // errors on the server side.
                payments.push([row.id, row.paymentPending.toFixed(2)]);
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

        // No actions pending.  Reset and exit.
        if (!this.paymentAmount && !this.refunding) { return; }

        let amount = this.pendingPayment();
        let done = false;

        this.billGrid.context.rowSelector.selected().forEach(index => {
            if (done) { return; }

            const row = this.billGrid.context.getRowByIndex(index);
            const owed = Number(row.balance_owed);

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
                this.gridDataSource.data.filter(e => e.id === payment[0])[0];

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
            if (row.balance_owed < 0) {
                this.billGrid.context.toggleSelectOneRow(row.id);
            }
        });
    }

    addBilling() {
        this.billingDialog.newXact = true;
        this.billingDialog.open().subscribe(data => {
            if (data) {
                this.context.refreshPatron().then(_ => this.billGrid.reload());
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

        console.debug('Voiding transactions', xactIds);

        // Grab the billings
        from(xactIds).pipe(concatMap(xactId => {
            return this.pcrud.search('mb', {xact: xactId}, {}, {authoritative: true})
                .pipe(tap(billing => {
                    if (billing.voided() === 'f') {
                        cents += billing.amount() * 100;
                        billIds.push(billing.id());
                    }
                }));
        })).toPromise()

        // Confirm the void action
            .then(_ => {
                this.voidAmount = cents / 100;
                return this.voidBillsDialog.open().toPromise();
            })

        // Do the void
            .then(confirmed => {
                if (!confirmed) { return empty(); }

                return this.net.requestWithParamList(
                    'open-ils.circ',
                    'open-ils.circ.money.billing.void',
                    [this.auth.token()].concat(billIds) // positional params
                ).toPromise();
            })

        // Clean up and refresh data
            .then(resp => {
                if (!resp || this.reportError(resp)) { return; }

                this.sessionVoided = (this.sessionVoided * 100 + cents) / 100;
                this.voidAmount = 0;

                this.context.refreshPatron()
                    .then(_ => this.billGrid.reload());
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
            // eslint-disable-next-line rxjs/no-nested-subscribe
            ).subscribe(resp => {
                if (!this.reportError(resp)) {
                    this.context.refreshPatron()
                        .then(_ => this.billGrid.reload());
                }
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
            this.errorDialog.dialogBody = evt.toString();
            this.errorDialog.open().toPromise();
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
            this.updatePendingColumn();
        });
    }

    showStatement(row: any) {
        if (!row) { return; }
        this.router.navigate(['/staff/circ/patron',
            this.patronId, 'bills', row.id, 'statement']);
    }
}

