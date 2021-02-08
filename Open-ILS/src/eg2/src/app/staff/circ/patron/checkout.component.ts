import {Component, OnInit, AfterViewInit, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Observable, empty, of, from} from 'rxjs';
import {tap, switchMap} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronManagerService, CircGridEntry} from './patron.service';
import {CheckoutParams, CheckoutResult, CircService} from '@eg/staff/share/circ/circ.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PrecatCheckoutDialogComponent} from './precat-dialog.component';
import {AudioService} from '@eg/share/util/audio.service';

@Component({
  templateUrl: 'checkout.component.html',
  selector: 'eg-patron-checkout'
})
export class CheckoutComponent implements OnInit {

    maxNoncats = 99; // Matches AngJS version
    checkoutNoncat: IdlObject = null;
    checkoutBarcode = '';
    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    dueDate: string;
    copiesInFlight: {[barcode: string]: boolean} = {};
    dueDateOptions: 0 | 1 | 2 = 0; // auto date; specific date; session date

    @ViewChild('nonCatCount') nonCatCount: PromptDialogComponent;
    @ViewChild('checkoutsGrid') checkoutsGrid: GridComponent;
    @ViewChild('precatDialog') precatDialog: PrecatCheckoutDialogComponent;

    constructor(
        private store: StoreService,
        private serverStore: ServerStoreService,
        private org: OrgService,
        private net: NetService,
        public circ: CircService,
        public patronService: PatronService,
        public context: PatronManagerService,
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

        if (this.store.getSessionItem('eg.circ.checkout.is_until_logout')) {
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
            patron_id: this.context.patron.id()
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

            if (this.copiesInFlight[this.checkoutBarcode]) {
                console.log('Item ' +
                    this.checkoutBarcode + ' is already mid-checkout');
                return Promise.resolve(null);
            }

            this.copiesInFlight[this.checkoutBarcode] = true;

            params.copy_barcode = this.checkoutBarcode;
            if (this.dueDateOptions > 0) { params.due_date = this.dueDate; }
            return Promise.resolve(params);
        }

        return Promise.resolve(null);
    }

    checkout() {
        this.collectParams()

        .then((params: CheckoutParams) => {
            if (params) {
                return this.circ.checkout(params);
            }
        })

        .then((result: CheckoutResult) => {
            if (result) {
                if (result.params.copy_barcode) {
                    delete this.copiesInFlight[result.params.copy_barcode];
                }
                this.dispatchResult(result);
            }
        });
    }

    dispatchResult(result: CheckoutResult) {

        if (result.success) {
            this.gridifyResult(result);
            this.resetForm();
            return;
        }

        switch (result.evt.textcode) {
            case 'ITEM_NOT_CATALOGED':
                this.audio.play('error.checkout.no_cataloged');
                this.handlePrecat(result);
                break;
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
            copyAlertCount: 0 // TODO
        };

        if (result.nonCatCirc) {

            entry.title = this.checkoutNoncat.name();
            entry.dueDate = result.nonCatCirc.duedate();

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
                this.store.removeSessionItem('eg.circ.checkout.is_until_logout');

            } else if (this.dueDateOptions === 1) { // 1 -> 2

                this.dueDateOptions = 2;
                this.store.setSessionItem('eg.circ.checkout.is_until_logout', true);

            } else { // 2 -> 1

                this.dueDateOptions = 1;
                this.store.removeSessionItem('eg.circ.checkout.is_until_logout');
            }

        } else {

            this.dueDateOptions = value;
            if (value === 2) {
                this.store.setSessionItem('eg.circ.checkout.is_until_logout', true);
            }
        }
    }

    handlePrecat(result: CheckoutResult) {
        this.precatDialog.open({size: 'lg'}).subscribe(values => {
            console.log('precat values', values);
        })
    }
}

