/* eslint-disable */
import {Component, ViewEncapsulation, OnInit, AfterViewInit, OnDestroy, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Observable, Subscription, Subject} from 'rxjs';
import {map, debounceTime, distinctUntilChanged, shareReplay} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ServerStoreService} from '@eg/core/server-store.service';
import {EgEvent} from '@eg/core/event.service';
import {InvoiceService} from './invoice.service';

@Component({
    templateUrl: 'details.component.html',
    styleUrls: ['details.component.css'],
    selector: 'eg-acq-invoice-details',
    encapsulation: ViewEncapsulation.None
})
export class InvoiceDetailsComponent implements OnInit, OnDestroy {

    @ViewChild('recordEditor', { static: false }) recordEditor: FmRecordEditorComponent;

    debouncedInputForRecord = new Subject<string>();
    debouncedInputForProvider = new Subject<string>();
    debouncedUpdateTotals = new Subject<IdlObject>();

    invoiceSubscription: Subscription;
    invoiceSubscription2: Subscription;

    duplicateInvIdentFound = false;
    totalCost = 0; uiTotalCost = 0;
    totalEncumbered = 0;
    totalPaid = 0; uiTotalPaid = 0;
    balanceOwed = 0; uiBalanceOwed = 0;
    errorWithTotals = false;
    fundSummary: any[] = [];
    providerName: string;

    initDone = false;
    showLegacyLinks = false;
    finishInvoiceActivation = false;

    activationBlocks: EgEvent[] = [];
    activationWarnings: EgEvent[] = [];
    activationEvent: EgEvent;
    venIdEditEnterToggled = false;

    linkedFmObservables: { [fmclass: string]: { [id: number]: Observable<string> } } = {};

    getLinkedFmObservable(fmclass: string, id: any): Observable<string> {
        // console.log('DetailsComponent, getLinkedFmObservable',fmclass,id);
        const fmselector = this.idl.getClassSelector(fmclass);
        if (!this.linkedFmObservables[fmclass]) {
            this.linkedFmObservables[fmclass] = {};
        }
        if (!this.linkedFmObservables[fmclass][id]) {
            this.linkedFmObservables[fmclass][id] = this.pcrud.search(fmclass,{id:id}).pipe(
                map(fmobj => fmobj[fmselector]()),
                shareReplay(1)
            );
        }
        return this.linkedFmObservables[fmclass][id];
    }

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private store: ServerStoreService,
        private router: Router,
        private invoiceService: InvoiceService,
    ) {}

    ngOnInit() {
        this.debouncedInputForRecord
            .pipe(
                debounceTime(500),
                distinctUntilChanged()
            )
            .subscribe(val => this.checkDuplicates(val));
        this.debouncedInputForProvider
            .pipe(
                debounceTime(500),
                distinctUntilChanged()
            )
            .subscribe(val => this.propagateProvider(val));
        this.debouncedUpdateTotals
            .pipe(
                debounceTime(500)
            )
            .subscribe(invoice => this.updateTotals(invoice));
        this.load().then(_ => {
            if (this.invoice()) {
                this.updateSummary(this.invoice());
                this.updateTotals(this.invoice());
                this.initDone = true;
            } else {
                this.invoiceSubscription = this.invoiceService.invoiceRetrieved.subscribe((emittedInvoice: IdlObject) => {
                    console.debug('InvoiceDetailsComponent, noticed an invoice retrieval',emittedInvoice);
                    this.updateSummary(emittedInvoice);
                    this.updateTotals(emittedInvoice);
                    this.initDone = true;
                });
            }
            this.invoiceSubscription2 = this.invoiceService.invoiceChange$.subscribe(() => {
                const clonedInvoice = this.idl.clone( this.invoice() );
                console.debug('InvoiceDetailsComponent, noticed invoiceChange$',clonedInvoice);
                this.safeUpdateTotals(clonedInvoice);
            });
        });
        console.warn('InvoiceDetailsComponent, this',this);
    }

    ngAfterViewInit() {
        if (this.recordEditor && this.invoice().close_date()) {
            if (this.recordEditor.mode == 'create' || this.recordEditor.mode == 'update') {
                this.recordEditor.mode = 'view';
                this.recordEditor.handleRecordChange();
            }
        }
    }

    ngOnDestroy() {
        if (this.invoiceSubscription) {
            this.invoiceSubscription.unsubscribe();
        }
        if (this.invoiceSubscription2) {
            this.invoiceSubscription2.unsubscribe();
        }
    }

    invoice(): IdlObject {
        return this.invoiceService.currentInvoice;
    }

    defleshedInvoice(): IdlObject {
        this.invoiceService.defleshInvoice();
        return this.invoiceService.currentInvoice;
    }

    async load(): Promise<any> {

        await this.loadUiPrefs();
    }

    checkDuplicates(val: string) {
        console.debug('InvoiceDetailsComponent, checkDuplicates', this.invoice().id(), val);

        this.invoiceService.currentInvoice.ischanged(true); // until we fix our use of fmEditForm with inv_ident
        this.invoiceService.checkDuplicateInvoiceVendorIdent(
            this.invoice().id(), val
        ).then( (results: any[]) => {
            console.warn('InvoiceDetailsComponent, checkDuplicate', results.length);
            if (results.length) {
                if(this.recordEditor.fmEditForm.form.get('inv_ident')) {
                    this.recordEditor.fmEditForm.form.controls['inv_ident'].setErrors({'duplicate':true});
                    this.recordEditor.fmEditForm.form.controls['inv_ident'].markAsTouched();
                } else {
                    console.warn('InvoiceDetailsComponent, no inv_ident in fmEditForm (yet?)');
                    this.duplicateInvIdentFound = true;
                }
            } else {
                if(this.recordEditor.fmEditForm.form.get('inv_ident')) {
                    this.recordEditor.fmEditForm.form.controls['inv_ident'].setErrors(null);
                    this.recordEditor.fmEditForm.form.controls['inv_ident'].updateValueAndValidity();
                } else {
                    console.warn('InvoiceDetailsComponent, no inv_ident in fmEditForm (yet?)');
                    this.duplicateInvIdentFound = false;
                }
            }
        });
    }

    async loadUiPrefs() {
        const settings = await this.store.getItemBatch(['ui.staff.acq.show_deprecated_links']); // getItemBatch returns a promise
        this.showLegacyLinks = settings['ui.staff.acq.show_deprecated_links'];
    }

    safeUpdateTotals(invoice: IdlObject) {
        this.debouncedUpdateTotals.next(invoice);
    }

    updateTotals(emittedInvoice: IdlObject) {
        try {
            console.debug('InvoiceDetailsComponent, updateTotals',emittedInvoice);

            if (!emittedInvoice) { return; }

            this.uiTotalCost = 0;
            this.uiTotalPaid = 0;
            this.uiBalanceOwed = 0;

            try {
                const filtered_items = emittedInvoice.items().filter( (i: IdlObject) => !i.isdeleted() ) || [];
                const filtered_entries = emittedInvoice.entries().filter( (e: IdlObject) => !e.isdeleted() ) || [];

                const uiTotalCostForItems = filtered_items.reduce(
                    (acc: number, ii: IdlObject) => acc + (Number(ii.cost_billed()) || 0), 0
                );
                const uiTotalCostForEntries = filtered_entries.reduce(
                    (acc: number, ie: IdlObject) => acc + (Number(ie.cost_billed()) || 0), 0
                );
                this.uiTotalCost = uiTotalCostForItems + uiTotalCostForEntries;

                const uiTotalPaidForItems = filtered_items.reduce(
                    (acc: number, ii: IdlObject) => acc + (Number(ii.amount_paid()) || 0), 0
                );
                const uiTotalPaidForEntries = filtered_entries.reduce(
                    (acc: number, ie: IdlObject) => acc + (Number(ie.amount_paid()) || 0), 0
                );
                this.uiTotalPaid = uiTotalPaidForItems + uiTotalPaidForEntries;
                this.uiBalanceOwed = (this.uiTotalCost - this.uiTotalPaid);

            } catch(E) {
                console.error('InvoiceDetailsComponent, error with updateTotals:',E);
            }

        } catch(E) {
            console.error('InvoiceDetailsComponent, updateTotals, error', E);
        }
    }

    updateSummary(emittedInvoice: IdlObject) {
        try {
            console.debug('InvoiceDetailsComponent, updateSummary',emittedInvoice);

            if (!emittedInvoice) { return; }

            this.totalCost = 0;
            this.totalEncumbered = 0;
            this.totalPaid = 0;
            this.balanceOwed = 0;

            this.errorWithTotals = false;
            try {
                const items = emittedInvoice.items();
                const entries = emittedInvoice.entries();

                const totalCostForItems = items.reduce(
                    (acc: number, ii: IdlObject) => acc + (Number(ii.cost_billed()) || 0), 0
                );
                const totalCostForEntries = entries.reduce(
                    (acc: number, ie: IdlObject) => acc + (Number(ie.cost_billed()) || 0), 0
                );
                this.totalCost = totalCostForItems + totalCostForEntries;

                const totalPaidForItems = items.reduce((acc: number, ii: IdlObject) => {
                    const fundDebit = ii.fund_debit();
                    if (fundDebit && !this.idl.toBoolean(fundDebit.encumbrance())) {
                        return acc + (Number(fundDebit.amount()) || 0);
                    }
                    return acc;
                }, 0);

                const totalEncumberedForItems = items.reduce((acc: number, ii: IdlObject) => {
                    const fundDebit = ii.fund_debit();
                    if (fundDebit && this.idl.toBoolean(fundDebit.encumbrance())) {
                        return acc + (Number(fundDebit.amount()) || 0);
                    }
                    return acc;
                }, 0);

                const totalPaidForEntries = entries.reduce((acc: number, ie: IdlObject) => {
                    const li = ie.lineitem();
                    const lids = li ? li.lineitem_details() : [];
                    let _acc = 0;
                    lids.forEach( (lid: IdlObject) => {
                        const fundDebit = lid.fund_debit();
                        if (fundDebit && !this.idl.toBoolean(fundDebit.encumbrance())) {
                            _acc += (Number(fundDebit.amount()) || 0);
                        }
                    });
                    return acc + _acc;
                }, 0);

                const totalEncumberedForEntries = entries.reduce((acc: number, ie: IdlObject) => {
                    const li = ie.lineitem();
                    const lids = li ? li.lineitem_details() : [];
                    let _acc = 0;
                    lids.forEach( (lid: IdlObject) => {
                        const fundDebit = lid.fund_debit();
                        if (fundDebit && this.idl.toBoolean(fundDebit.encumbrance())) {
                            _acc += (Number(fundDebit.amount()) || 0);
                        }
                    });
                    return acc + _acc;
                }, 0);

                this.totalPaid = totalPaidForItems + totalPaidForEntries;
                this.totalEncumbered = totalEncumberedForItems + totalEncumberedForEntries;
            } catch(E) {
                console.error('InvoiceDetailsComponent, error with updateSummary:',E);
                this.errorWithTotals = true;
            }

            this.updateFundSummary();
        } catch(E) {
            console.error('InvoiceDetailsComponent, updateSummary, error', E);
        }
    }

    updateFundSummary() {
        if (this.invoice().id()) {
            this.invoiceService.getInvFundSummary( this.invoice().id() ).then(
                result => {
                    this.fundSummary = result;
                }).catch(error => {
                console.error('InvoiceDetailsComponent, error retrieving fund summary', error);
            });
        }
    }

    isUnSet(value: any): boolean {
        return value === undefined || value === null || value === '';
    }

    propagateProvider(val: any) {
        console.debug('provider val',val);
        // if (!this.isUnSet(val)) {
        this.recordEditor._record.shipper( val.fm );
        // }
    }

    refresh(heavy = false) {
        console.debug('InvoiceDetailsComponent, refresh page');
        if (heavy) {
            location.href = location.href; // sledgehammer
        } else {
            this.router.navigateByUrl('/', {skipLocationChange: true}).then(() => {
                // this.router.navigate([decodeURI(this.location.path())]);
                this.router.navigate(['/staff/acq/invoice/' + this.invoice().id()]);
            });
        }
    }

}
