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
import {CreditCardDialogComponent
    } from '@eg/staff/share/billing/credit-card-dialog.component';
import {BillingService, CreditCardPaymentParams} from '@eg/staff/share/billing/billing.service';

interface BillGridEntry extends CircDisplayInfo {
    xact: IdlObject // mbt
    billingLocation?: string;
    paymentPending?: number;
}

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
    entries: BillGridEntry[];
    convertChangeToCredit = false;
    receiptOnPayment = false;
    applyingPayment = false;
    numReceipts = 1;
    ccPaymentParams: CreditCardPaymentParams;
    disableAutoPrint = false;

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
        private billing: BillingService,
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
            'ui.circ.billing.amount_limit',
            'circ.staff_client.do_not_auto_attempt_print'
        ]).then(sets => {
            this.maxPayAmount = sets['ui.circ.billing.amount_limit'] || 100000;
            this.warnPayAmount = sets['ui.circ.billing.amount_warn'] || 1000;

            const noPrint = sets['circ.staff_client.do_not_auto_attempt_print'];
            if (noPrint && noPrint.includes('Bill Pay')) {
                this.disableAutoPrint = true;
            }
        });
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

    // In refresh mode, only fetch the requested xacts, with updated user
    // summary, and slot them back into the entries array.
    load(refreshXacts?: number[]): Promise<any> {

        let entries = [];
        this.summary = null;
        this.gridDataSource.requestingData = true;

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.transactions.for_billing',
            this.auth.token(), this.patronId, refreshXacts

        ).pipe(tap(resp => {

            if (!this.summary) { // 1st response is summary
                this.summary = resp;
                return;
            }

            if (refreshXacts) {

                // Slot the updated xact back into place
                entries.push(this.formatForDisplay(resp));
                entries = entries.map(e => {
                    if (e.xact.id() === resp.id()) {
                        return this.formatForDisplay(resp);
                    }
                    return e;
                });

            } else {
                entries.push(this.formatForDisplay(resp));
            }
        })).toPromise()

        .then(_ => {
            this.gridDataSource.requestingData = false;
            this.entries = entries;
            this.billGrid.reload();
        });
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
        const owedSelected = this.owedSelected();

        if (amt >= owedSelected) {
            return {
                payment : owedSelected,
                change : amt - owedSelected
            }
        }

        return {payment : amt, change : 0};
    }

    disablePayment(): boolean {
        if (!this.billGrid) { return true; } // still loading

        return (
            this.applyingPayment ||
            !this.pendingPayment() ||
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
        .then(_ => this.load(payments.map(p => p[0]))) // load xact IDs
        .then(_ => this.context.refreshPatron())
        .catch(msg => console.debug('Payment Canceled:', msg))
        .finally(() => this.applyingPayment = false);
    }

    handlePayReceipt(payments: Array<Array<number>>, paymentIds: number[]): Promise<any> {

        if (this.disableAutoPrint || !this.receiptOnPayment) {
            return Promise.resolve();
        }

        // TODO
        // return this.printer.pr
    }

    compilePayments(): Array<Array<number>> {
        const payments = [];
        this.entries.forEach(row => {
            if (row.paymentPending) {
                payments.push([row.xact.id(), row.paymentPending]);
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
        this.entries.forEach(row => row.paymentPending = 0);

        var amount = this.pendingPayment();
        let done = false;

        this.billGrid.context.rowSelector.selected().forEach(index => {
            if (done) { return; }

            const row = this.billGrid.context.getRowByIndex(index);
            const owed = Number(row.xact.summary().balance_owed());

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
}

