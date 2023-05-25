import {Component, OnInit, OnDestroy, ChangeDetectorRef, ViewChild} from '@angular/core';
import {Subscription, Subject, firstValueFrom, lastValueFrom} from 'rxjs';
import {debounceTime, takeUntil, defaultIfEmpty} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
// import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {InvoiceService} from './invoice.service';
import {LineitemService} from '../lineitem/lineitem.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {DisencumberChargeDialogComponent} from './disencumber-charge-dialog.component';

@Component({
    templateUrl: 'charges.component.html',
    styleUrls:  ['charges.component.css'],
    selector: 'eg-acq-invoice-charges'
})
export class InvoiceChargesComponent implements OnInit, OnDestroy {

    private permissions: any;

    showBody = false;
    canModify = false;
    editCount = 0;
    inBatch = false;
    tempId = -1;
    invoiceSubscription: Subscription;
    chargeMap: any = {};
    amountPaidMap: any = {};

    private costBilledChangeSubject = new Subject<{ charge: IdlObject; value: any }>();
    private amountPaidChangeSubject = new Subject<{ charge: IdlObject; value: any }>();
    private destroy$ = new Subject<void>();

    owners: number[];

    @ViewChild('disencumberChargeDialog') disencumberChargeDialog: DisencumberChargeDialogComponent;
    @ViewChild('stopPercentAlertDialog') stopPercentAlertDialog: AlertDialogComponent;
    @ViewChild('stopPercentConfirmDialog') stopPercentConfirmDialog: ConfirmDialogComponent;
    @ViewChild('warnPercentConfirmDialog') warnPercentConfirmDialog: ConfirmDialogComponent;

    constructor(
        private idl: IdlService,
        private changeDetector: ChangeDetectorRef,
        // private net: NetService,
        private evt: EventService,
        private auth: AuthService,
        private perm: PermService,
        private org: OrgService,
        private liService: LineitemService,
        public  invoiceService: InvoiceService
    ) {}

    ngOnInit() {

        this.loadPerms();

        // Other times we have to wait for it.
        this.invoiceSubscription = this.invoiceService.invoiceRetrieved.subscribe((invoice) => {
            console.debug('InvoiceChargesComponent, invoice at charges ngOnInit after invoiceRetrieved emit',invoice);
            this.showBody = invoice.items()?.length > 0;
            this.canModify = invoice.close_date() ? false : true;
            this.populateChargeMap();
        });
        if (this.invoiceService.currentInvoice) {
            this.showBody = this.invoiceService.currentInvoice.items()?.length > 0;
            this.canModify = this.invoiceService.currentInvoice.close_date() ? false : true;
            this.populateChargeMap();
        }

        this.costBilledChangeSubject.pipe(
            debounceTime(1000),
            takeUntil(this.destroy$) // Unsubscribe when destroy$ emits
        ).subscribe(({charge, value }) => {
            console.debug('InvoiceChargesComponent, debounced costBilledChangeSubject');
            this._handleCostBilledChange(charge, value);
        });

        this.amountPaidChangeSubject.pipe(
            debounceTime(1000),
            takeUntil(this.destroy$) // Unsubscribe when destroy$ emits
        ).subscribe(({charge, value }) => {
            console.debug('InvoiceChargesComponent, debounced costBilledChangeSubject');
            this._handleAmountPaidChange(charge, value);
        });

        this.owners = this.org.ancestors(this.auth.user().ws_ou(), true);

        console.debug('InvoiceChargesComponent',this);
    }

    ngOnDestroy() {
        if (this.invoiceSubscription) {
            this.invoiceSubscription.unsubscribe();
        }
        this.destroy$.next(); // Emit a value to complete the subscription
        this.destroy$.complete(); // Mark the subject as completed
    }

    async loadPerms(): Promise<void> {
        if (this.permissions) {
            return;
        }
        this.permissions = await this.perm.hasWorkPermAt(['ACQ_ALLOW_OVERSPEND'], true);
    }

    invoice(): IdlObject {
        return this.invoiceService.currentInvoice;
    }

    newCharge() {
        console.debug('InvoiceChargesComponent, newCharge');
        this.showBody = true;
        const chg = this.idl.create('acqii');
        chg.id(this.tempId--);
        chg.isnew(true);
        chg.invoice(this.invoice().id());
        if (!this.invoice().items()) {
            this.invoice().items([]);
        }
        this.invoice().items().unshift(chg);
        this.editCharge(chg); // start in edit mode
        this.populateChargeMap();
    }

    chargeValid(charge: IdlObject): boolean {
        if (!charge.inv_item_type()) {
            // console.warn('need inv_item_type', charge);
            return false;
        }
        if (!charge.fund() && this.isChargeFundRequired(charge) ) {
            // console.warn('need fund', charge);
            return false;
        }
        if (charge.cost_billed() === null || isNaN(Number(charge.cost_billed()))) {
            // console.log('cost_billed not right', charge);
            return false;
        }
        if (charge.amount_paid() === null || isNaN(Number(charge.amount_paid()))) {
            // console.log('amount_paid not right', charge);
            return false;
        }
        return true;
    }

    allChargesValid(): boolean {
        let valid = true; // let invalid_count = 0;
        (this.invoice().items() || []).forEach( (charge: IdlObject) => {
            if (! this.chargeValid(charge) ) {
                valid = false;
                // invalid_count++;
            }
        });
        // console.log('invalid charge count', invalid_count);
        return valid;
    }

    atLeastOneChargeIsChangedOrNewOrDeleted(): boolean {
        let isSaveWorthy = false; // let worthy_count = 0;
        (this.invoice().items() || []).forEach( (charge: IdlObject) => {
            if (charge.ischanged() || charge.isnew() || charge.isdeleted()) {
                isSaveWorthy = true;
                // worthy_count++;
            }
        });
        // console.log('charge saveable count', worthy_count);
        return isSaveWorthy;
    }

    updateCRUDflags(obj: IdlObject) {
        if (!obj.id()) {
            obj.isnew(true);
            obj.ischanged(false);
        } else {
            obj.ischanged(true);
        }
    }

    saveCharge(charge: IdlObject) {
        console.debug('InvoiceChargesComponent, saveCharge',charge);
        if (!this.chargeValid(charge)) {
            return;
        }

        this.updateCRUDflags(charge);

        this.editCount = 0; this.inBatch = false;
        this.invoice().items( [charge] );

        // this should get us fund debits
        this.invoiceService.updateInvoice().then( resp => {
            console.warn('saveCharge -> updateInvoice',resp);
        });
        // this would not: this.invoiceService.updateInvoiceItem(charge);
    }

    resetBatch() {
        this.editCount = 0; this.inBatch = false;
    }

    saveAllCharges() {
        if (!this.allChargesValid()) {
            return;
        }

        (this.invoice().items() || []).forEach( (charge: IdlObject) => {
            this.updateCRUDflags(charge);
        });

        this.resetBatch();

        this.invoiceService.updateInvoice().then( resp => {
            console.warn('saveAllCharges -> updateInvoice',resp);
        });
    }

    editCharge(charge: IdlObject) {
        console.debug('InvoiceChargesComponent, editCharge');
        charge.ischanged(true);
        if (++this.editCount > 1) {
            this.inBatch = true;
        }
    }

    batchEdit() {
        console.debug('InvoiceChargesComponent, batchEdit');
        this.editCount = 0; this.inBatch = false;
        (this.invoice().items() || []).forEach( (charge: IdlObject) => {
            this.editCharge(charge);
        });
    }

    canDisencumber(charge: IdlObject): boolean {
        if (!this.invoice() || !this.invoice().close_date()) {
            return false; // bail if no invoice?! or closed?
        }
        if (!charge.fund_debit()) {
            return false; // that which is not encumbered cannot be disencumbered
        }

        const debit = charge.fund_debit();
        if (debit.encumbrance() === 'f') {
            return false; // that which is expended cannot be disencumbered
        }
        /* if (debit.invoice_entry()) {
            return false; // we shouldn't actually be a invoice_item that is
                          // linked to an invoice_entry, but if we are,
                          // do NOT touch
        }
        if (debit.invoice_items() && debit.invoice_items().length) {
            return false; // we're linked to an invoice item, so the disposition of the
                          // invoice entry should govern things
        }*/
        if (Number(debit.amount()) === 0) {
            return false; // we're already at zero
        }
        return true; // we're likely OK to disencumber
    }

    canRemove(charge: IdlObject): boolean {

        return charge.isnew();
    }

    removeCharge(charge: IdlObject) {
        if (!charge.isnew()) { return; }

        this.invoice().items(
            this.invoice().items().filter((item: IdlObject) => item.id() !== charge.id())
        );
        this.invoiceService.changeNotify();
    }

    canDelete(charge: IdlObject): boolean {

        return !charge.isnew() && !charge.isdeleted() && !charge.po_item();
    }

    deleteCharge(charge: IdlObject) {
        if (!charge.isnew() && !charge.isdeleted()) {
            charge.isdeleted(true);
            this.invoiceService.changeNotify();
        }
    }

    canUndelete(charge: IdlObject): boolean {

        return !charge.isnew() && charge.isdeleted() && !charge.po_item();
    }

    undeleteCharge(charge: IdlObject) {
        if (!charge.isnew() && charge.isdeleted()) {
            charge.isdeleted(false);
            this.invoiceService.changeNotify();
        }
    }

    isChargeFundRequired(charge: IdlObject): boolean {
        // if the inv_item_type is prorate-able, then no fund is required
        if (!charge) { return false; }
        if (!charge.inv_item_type()) { return false; }
        if (typeof charge.inv_item_type() === 'object') {
            return charge.inv_item_type().prorate() !== 't';
        } else {
            return this.invoiceService.invItemTypeMap[charge.inv_item_type()].prorate() !== 't';
        }
    }

    handleChangedChargeType(charge: IdlObject, event_obj: any) {
        // event_obj ~ {id: 'SUB', label: 'Serial Subscription', fm: aiit}
        console.debug('invoiceChargesComponent, handleChangedChargeType',charge,event_obj);
        charge.inv_item_type(event_obj ? event_obj.id : null);
        if (event_obj && event_obj.fm.prorate() == 't') {
            charge.fund(null); // proratable charges get distributed amongst available funds
        }
        this.invoiceService.changeNotify();
    }

    async fundCheck(fundId: number, amountDelta: number): Promise<boolean> {
        console.debug('invoiceChargesComponent, fundCheck',fundId,amountDelta);
        const extra_and_emit = () => {
            // any extra behavior? not for the new generic version of this method
            return true;
        };

        if ( fundId !== null && !isNaN(amountDelta) && amountDelta > 0 ) {
            /* this may encumber more funds, so test thresholds */
            let results: any;
            try {
                results = await firstValueFrom( this.invoiceService.checkAmountAgainstFunds([fundId], amountDelta) );
                console.debug('invoiceChargesComponent, handleInvoiceEntryMoney, funds check', results);
            } catch(E) {
                console.error('invoiceChargesComponent, handleInvoiceEntryMoney, 1: error checking amount against fund(s)', E);
                return false;
            }
            try {
                const evt = this.evt.parse(results);
                if (!evt) {
                    let warn_triggered = false;
                    let stop_triggered = false;
                    let can_override_stop_for_all_funds_involved = true;
                    const stop_funds = [];
                    const warn_funds = [];
                    for (const {fundId, stop, warn} of results) {
                        const fund = await this.liService.getFund(fundId);
                        console.debug('invoiceChargesComponent, handleInvoiceEntryMoney, funds check, fund', fund);
                        if (stop) {
                            stop_triggered = true;
                            stop_funds.push(fund);
                            if (!this.permissions.ACQ_ALLOW_OVERSPEND.includes(fund.org())) {
                                can_override_stop_for_all_funds_involved = false;
                            }
                        } else if (warn) {
                            warn_triggered = true;
                            warn_funds.push(fund);
                        }
                    }
                    if (stop_triggered) {
                        console.warn('invoiceChargesComponent, stop /* ACQ_FUND_EXCEEDS_STOP_PERCENT */');
                        if (can_override_stop_for_all_funds_involved) {
                            // this.stopPercentConfirmDialog.funds = stop_funds;
                            const response = await firstValueFrom(
                                this.stopPercentConfirmDialog.open()
                            );
                            return response ? extra_and_emit() : false;
                        } else {
                            // this.stopPercentAlertDialog.funds = stop_funds;
                            await lastValueFrom(
                                this.stopPercentAlertDialog.open().pipe(defaultIfEmpty(null))
                            );
                            return false;
                        }
                    } else if (warn_triggered) {
                        console.warn('invoiceChargesComponent, warn /* ACQ_FUND_EXCEEDS_WARN_PERCENT */');
                        // this.warnPercentConfirmDialog.funds = warn_funds;
                        const response = await firstValueFrom(
                            this.warnPercentConfirmDialog.open()
                        );
                        return response ? extra_and_emit() : false;
                    }
                    return true;
                } else {
                    console.error('invoiceChargesComponent, handleInvoiceEntryMoney, 2: error checking amount against fund', evt);
                    return false;
                }
            } catch(E) {
                console.error('invoiceChargesComponent, handleInvoiceEntryMoney, 3: error checking amount against fund', E);
                return false;
            }
        } else {
            /* but no reason not to let someone reduce a value */
            return extra_and_emit();
        }
    }

    isUnSet(value: any): boolean {
        return value === undefined || value === null || value === '';
    }

    handleCostBilledChange(charge: IdlObject, value: any) {
        console.debug('invoiceChargesComponent, handleCostBilledChange', charge, value);
        this.costBilledChangeSubject.next({ charge, value });
        this.invoiceService.changeNotify();
    }

    _handleCostBilledChange(charge: IdlObject, value: any) {
        console.debug('invoiceChargesComponent, _handleCostBilledChange', charge, value);
        const original_value = charge.cost_billed() || 0;
        charge.cost_billed(value);
        // originally was propagate if unset
        console.debug('invoiceChargesComponent, _handleCostBilledChange, setting amount paid as well');
        if (charge.amount_paid() === undefined || charge.amount_paid() === null || charge.amount_paid() === 0 || charge.amount_paid() === '') {
            this.handleAmountPaidChange(charge, value);
        }
    }

    handleAmountPaidChange(charge: IdlObject, value: any) {
        console.debug('invoiceChargesComponent, handleAmountPaidChange', charge, value);
        this.amountPaidChangeSubject.next({ charge, value });
        this.invoiceService.changeNotify();
    }

    _handleAmountPaidChange(charge: IdlObject, value: any) {
        console.debug('invoiceChargesComponent, _handleAmountPaidChange', charge, value);
        const numeric_value = parseFloat(value) || 0;
        const original_value = parseFloat(charge.amount_paid()) || 0;
        this.fundCheck(charge.fund(), numeric_value - original_value).then(
            (keep: boolean) => {
                if (keep) {
                    console.debug('invoiceChargesComponent, _handleAmountPaidChange, keeping',numeric_value);
                    charge.amount_paid(numeric_value);
                    this.amountPaidMap[charge.id()] = numeric_value;
                } else {
                    console.debug('invoiceChargesComponent, _handleAmountPaidChange, not keeping',original_value);
                    charge.amount_paid(original_value);
                    this.amountPaidMap[charge.id()] = original_value;
                }
                this.populateChargeMap();
                this.changeDetector.detectChanges();
                this.invoiceService.changeNotify();
            }
        );
    }

    getChargeMapKeys() {
        return Object.keys(this.chargeMap);
    }

    trackByKey(index, key) {
        return key;
    }

    populateChargeMap() {
        console.debug('invoiceChargesComponent, populateChargeMap, before', this.amountPaidMap);
        this.chargeMap = {}; // more likely to trigger change detection
        this.amountPaidMap = {}; // more likely to trigger change detection
        this.invoice().items().forEach(item => {
            this.chargeMap[item.id()] = item;
            this.amountPaidMap[item.id()] = item.amount_paid();
        });
        setTimeout(() => this.changeDetector.detectChanges(), 0);
        console.debug('invoiceChargesComponent, populateChargeMap, after', this.amountPaidMap);
    }
}

