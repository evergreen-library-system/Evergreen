import {Component, OnInit, AfterViewInit, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Observable, empty, of, from} from 'rxjs';
import {tap, switchMap} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService, CircGridEntry} from './patron.service';
import {CheckoutParams, CheckoutResult, CircService
    } from '@eg/staff/share/circ/circ.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CopyAlertsDialogComponent
    } from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {BarcodeSelectComponent
    } from '@eg/staff/share/barcodes/barcode-select.component';

const SESSION_DUE_DATE = 'eg.circ.checkout.is_until_logout';

@Component({
  templateUrl: 'checkout.component.html',
  selector: 'eg-patron-checkout'
})
export class CheckoutComponent implements OnInit, AfterViewInit {

    maxNoncats = 99; // Matches AngJS version
    checkoutNoncat: IdlObject = null;
    checkoutBarcode = '';
    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    dueDate: string;
    dueDateOptions: 0 | 1 | 2 = 0; // auto date; specific date; session date

    private copiesInFlight: {[barcode: string]: boolean} = {};

    @ViewChild('nonCatCount')
        private nonCatCount: PromptDialogComponent;
    @ViewChild('checkoutsGrid')
        private checkoutsGrid: GridComponent;
    @ViewChild('copyAlertsDialog')
        private copyAlertsDialog: CopyAlertsDialogComponent;
    @ViewChild('barcodeSelect')
        private barcodeSelect: BarcodeSelectComponent;

    constructor(
        private store: StoreService,
        private serverStore: ServerStoreService,
        private org: OrgService,
        private net: NetService,
        public circ: CircService,
        public patronService: PatronService,
        public context: PatronContextService,
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
            patron_id: this.context.summary.id
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
            if (result) {
                this.dispatchResult(result);
                return result;
            }
        })

        .finally(() => delete this.copiesInFlight[barcode]);
    }

    dispatchResult(result: CheckoutResult) {
        if (result.success) {
            this.gridifyResult(result);
            this.resetForm();
            return;
        }
    }

    resetForm() {

        if (this.dueDateOptions < 2) {
            // Due date is not configured to persist.
            this.dueDateOptions = 0;
            this.dueDate = null;
        }

        this.checkoutBarcode = '';
        this.checkoutNoncat = null;
        this.focusInput();
    }

    gridifyResult(result: CheckoutResult) {
        const entry: CircGridEntry = {
            copy: result.copy,
            circ: result.circ,
            dueDate: null,
            copyAlertCount: 0, // TODO
            nonCatCount: 0
        };

        if (result.nonCatCirc) {

            entry.title = this.checkoutNoncat.name();
            entry.dueDate = result.nonCatCirc.duedate();
            entry.nonCatCount = result.params.noncat_count;

        } else {

            if (result.record) {
                entry.title = result.record.title();
                entry.author = result.record.author();
                entry.isbn = result.record.isbn();

            } else if (result.copy) {
                entry.title = result.copy.dummy_title();
                entry.author = result.copy.dummy_author();
                entry.isbn = result.copy.dummy_isbn();
            }

            if (result.circ) {
                entry.dueDate = result.circ.due_date();
            }
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
                if (modified) {
                    // TODO: verify the modiifed alerts are present
                    // or go fetch them.
                    this.checkoutsGrid.reload();
                }
            }
        );
    }
}

