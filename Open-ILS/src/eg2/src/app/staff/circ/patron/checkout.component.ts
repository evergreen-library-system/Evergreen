import {Component, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Subscription, Observable, empty, of, from} from 'rxjs';
import {switchMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService, CircGridEntry} from './patron.service';
import {CheckoutParams, CheckoutResult, CircService
} from '@eg/staff/share/circ/circ.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CopyAlertsDialogComponent
} from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {BarcodeSelectComponent
} from '@eg/staff/share/barcodes/barcode-select.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {AuthService} from '@eg/core/auth.service';
import {PrintService} from '@eg/share/print/print.service';

const SESSION_DUE_DATE = 'eg.circ.checkout.is_until_logout';

@Component({
    templateUrl: 'checkout.component.html',
    selector: 'eg-patron-checkout'
})
export class CheckoutComponent implements OnInit, AfterViewInit {
    static autoId = 0;

    // eslint-disable-next-line no-magic-numbers
    maxNoncats = 99; // Matches AngJS version
    checkoutNoncat: IdlObject = null;
    checkoutBarcode = '';
    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    dueDate: string;
    dueDateOptions: 0 | 1 | 2 = 0; // auto date; specific date; session date
    dueDateInvalid = false;
    printOnComplete = true;
    strictBarcode = false;

    private copiesInFlight: {[barcode: string]: boolean} = {};

    @ViewChild('nonCatCount')
    private nonCatCount: PromptDialogComponent;
    @ViewChild('checkoutsGrid')
    private checkoutsGrid: GridComponent;
    @ViewChild('copyAlertsDialog')
    private copyAlertsDialog: CopyAlertsDialogComponent;
    @ViewChild('barcodeSelect')
    private barcodeSelect: BarcodeSelectComponent;
    @ViewChild('receiptEmailed')
    private receiptEmailed: StringComponent;

    constructor(
        private router: Router,
        private store: StoreService,
        private serverStore: ServerStoreService,
        private org: OrgService,
        private pcrud: PcrudService,
        private net: NetService,
        public circ: CircService,
        public patronService: PatronService,
        public context: PatronContextService,
        private toast: ToastService,
        private auth: AuthService,
        private printer: PrintService,
        private audio: AudioService
    ) {}

    ngOnInit() {
        this.circ.getNonCatTypes();

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return from(this.context.checkouts);
        };

        this.cellTextGenerator = {
            title: row => row.title
        };

        if (this.store.getSessionItem(SESSION_DUE_DATE)) {
            this.dueDate = this.store.getSessionItem('eg.circ.checkout.due_date');
            this.toggleDateOptions(2);
        }

        this.serverStore.getItem('circ.staff_client.do_not_auto_attempt_print')
            .then(noPrint => {
                this.printOnComplete = !(
                    noPrint &&
                noPrint.includes('Checkout')
                );
            });

        this.serverStore.getItem('circ.checkout.strict_barcode')
            .then(strict => this.strictBarcode = strict);
    }

    ngAfterViewInit() {
        this.focusInput();
    }

    focusInput() {
        const input = document.getElementById('barcode-input');
        if (input) { input.focus(); }
    }

    collectParams(): Promise<CheckoutParams> {

        const params: CheckoutParams = {
            patron_id: this.context.summary.id,
            _checkbarcode: this.strictBarcode,
            _worklog: {
                user: this.context.summary.patron.family_name(),
                patron_id: this.context.summary.id
            }
        };

        if (this.checkoutNoncat) {

            return this.noncatPrompt().toPromise().then(count => {
                if (!count) { return null; }
                params.noncat = true;
                params.noncat_count = count;
                params.noncat_type = this.checkoutNoncat.id();
                return params;
            });

        } else if (this.checkoutBarcode) {

            if (this.dueDateOptions > 0) { params.due_date = this.dueDate; }

            return this.barcodeSelect.getBarcode('asset', this.checkoutBarcode)
                .then(selection => {
                    if (selection) {
                        params.copy_id = selection.id;
                        params.copy_barcode = selection.barcode;
                        return params;
                    } else {
                    // User canceled the multi-match selection dialog.
                        return null;
                    }
                });
        }

        return Promise.resolve(null);
    }

    checkout(params?: CheckoutParams, override?: boolean): Promise<CheckoutResult> {

        if (this.dueDateInvalid) {
            return Promise.resolve(null);
        }

        let barcode;
        const promise = params ? Promise.resolve(params) : this.collectParams();

        return promise.then((collectedParams: CheckoutParams) => {
            if (!collectedParams) { return null; }

            barcode = collectedParams.copy_barcode || '';

            if (barcode) {

                if (this.copiesInFlight[barcode]) {
                    console.debug('Item ' + barcode + ' is already mid-checkout');
                    return null;
                }

                this.copiesInFlight[barcode] = true;
            }

            return this.circ.checkout(collectedParams);
        })

            .then((result: CheckoutResult) => {
                if (result && result.success) {
                    this.gridifyResult(result);
                }
                delete this.copiesInFlight[barcode];
                this.resetForm();
                return result;
            })

            .finally(() => delete this.copiesInFlight[barcode]);
    }

    resetForm() {
        this.checkoutBarcode = '';
        this.checkoutNoncat = null;
        this.focusInput();
    }

    gridifyResult(result: CheckoutResult) {
        const entry: CircGridEntry = {
            index: CheckoutComponent.autoId++,
            copy: result.copy,
            circ: result.circ,
            dueDate: null,
            copyAlertCount: 0,
            nonCatCount: 0,
            record: result.record,
            volume: result.volume,
            patron: result.patron,
            title: result.title,
            author: result.author,
            isbn: result.isbn
        };

        if (result.nonCatCirc) {

            entry.title = this.checkoutNoncat.name();
            entry.dueDate = result.nonCatCirc.duedate();
            entry.nonCatCount = result.params.noncat_count;

        } else if (result.circ) {
            entry.dueDate = result.circ.due_date();
        }

        if (entry.copy) {
            // Fire and forget this one

            this.pcrud.search('aca',
                {copy : entry.copy.id(), ack_time : null}, {}, {atomic: true}
            ).subscribe(alerts => entry.copyAlertCount = alerts.length);
        }

        this.context.checkouts.unshift(entry);
        this.checkoutsGrid.reload();

        // update summary data
        this.context.refreshPatron();
    }

    noncatPrompt(): Observable<number> {
        return this.nonCatCount.open()
            .pipe(switchMap(count => {

                if (count === null || count === undefined) {
                    return empty(); // dialog canceled
                }

                // Even though the prompt has a type and min/max values,
                // users can still manually enter bogus values.
                count = Number(count);
                if (count > 0 && count < this.maxNoncats) {
                    return of(count);
                } else {
                // Bogus value.  Try again
                    return this.noncatPrompt();
                }
            }));
    }

    setDueDate(iso: string) {
        const date = new Date(Date.parse(iso));
        this.dueDateInvalid = (date < new Date());
        this.dueDate = iso;
        this.store.setSessionItem('eg.circ.checkout.due_date', this.dueDate);
    }


    // 0: use server due date
    // 1: use specific due date once
    // 2: use specific due date until the end of the session.
    toggleDateOptions(value: 1 | 2) {
        if (this.dueDateOptions > 0) {

            if (value === 1) { // 1 or 2 -> 0
                this.dueDateOptions = 0;
                this.store.removeSessionItem(SESSION_DUE_DATE);

            } else if (this.dueDateOptions === 1) { // 1 -> 2

                this.dueDateOptions = 2;
                this.store.setSessionItem(SESSION_DUE_DATE, true);

            } else { // 2 -> 1

                this.dueDateOptions = 1;
                this.store.removeSessionItem(SESSION_DUE_DATE);
            }

        } else {

            this.dueDateOptions = value;
            if (value === 2) {
                this.store.setSessionItem(SESSION_DUE_DATE, true);
            }
        }
    }

    selectedCopyIds(rows: CircGridEntry[]): number[] {
        return rows
            .filter(row => row.copy)
            .map(row => Number(row.copy.id()));
    }

    openItemAlerts(rows: CircGridEntry[], mode: string) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.mode = mode;
        this.copyAlertsDialog.open({size: 'lg'}).subscribe(
            modified => {
                if (modified && modified.newAlerts.length > 0) {
                    rows.forEach(row => row.copyAlertCount++);
                    this.checkoutsGrid.reload();
                }
            }
        );
    }

    toggleStrictBarcode(active: boolean) {
        if (active) {
            this.serverStore.setItem('circ.checkout.strict_barcode', true);
        } else {
            this.serverStore.removeItem('circ.checkout.strict_barcode');
        }
    }

    patronHasEmail(): boolean {
        if (!this.context.summary) { return false; }
        const patron = this.context.summary.patron;
        return (
            patron.email() &&
            patron.email().match(/.*@.*/) !== null
        );
    }

    mayEmailReceipt(): boolean {
        if (!this.context.summary) { return false; }
        const patron = this.context.summary.patron;
        const setting = patron.settings()
            .filter(s => s.name() === 'circ.send_email_checkout_receipts')[0];

        return (
            this.patronHasEmail() &&
            setting &&
            setting.value() === 'true' // JSON encoded
        );
    }

    quickReceipt() {
        if (this.mayEmailReceipt()) {
            this.emailReceipt();
        } else {
            this.printReceipt();
        }
    }

    doneAutoReceipt() {
        if (this.mayEmailReceipt()) {
            this.emailReceipt(true);
        } else if (this.printOnComplete) {
            this.printReceipt(true);
        }
    }

    emailReceipt(redirect?: boolean) {
        if (this.patronHasEmail() && this.context.checkouts.length > 0) {
            return this.net.request(
                'open-ils.circ',
                'open-ils.circ.checkout.batch_notify.session.atomic',
                this.auth.token(),
                this.context.summary.id,
                this.context.checkouts.map(c => c.circ.id())
            ).subscribe(_ => {
                this.toast.success(this.receiptEmailed.text);
                if (redirect) { this.doneRedirect(); }
            });
        }
    }

    printReceipt(redirect?: boolean) {
        if (this.context.checkouts.length === 0) { return; }

        if (redirect) {
            // Wait for the print job to be queued before redirecting
            const sub: Subscription =
                this.printer.printJobQueued$.subscribe(_ => {
                    sub.unsubscribe();
                    this.doneRedirect();
                });
        }

        this.printer.print({
            printContext: 'receipt',
            templateName: 'checkout',
            contextData: {checkouts: this.context.checkouts}
        });
    }

    doneRedirect() {
        // Clear the assumed hold recipient since we're done with
        // this patron.
        this.store.removeLoginSessionItem('eg.circ.patron_hold_target');
        this.router.navigate(['/staff/circ/patron/bcsearch']);
    }
}

