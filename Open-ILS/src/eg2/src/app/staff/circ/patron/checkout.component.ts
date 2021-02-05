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

    @ViewChild('nonCatCount') nonCatCount: PromptDialogComponent;
    @ViewChild('checkoutsGrid') checkoutsGrid: GridComponent;

    constructor(
        private org: OrgService,
        private net: NetService,
        public circ: CircService,
        public patronService: PatronService,
        public context: PatronManagerService
    ) {}

    ngOnInit() {
        this.circ.getNonCatTypes();

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return from(this.context.checkouts);
        };

        this.cellTextGenerator = {
            title: row => row.title
        };
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
            params.copy_barcode = this.checkoutBarcode;
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
                if (result.success) {
                    this.gridifyResult(result);
                    this.resetForm();
                }
            }
        });
    }

    resetForm() {
        this.checkoutBarcode = '';
        this.checkoutNoncat = null;
        this.focusInput();
    }

    gridifyResult(result: CheckoutResult) {
        const entry: CircGridEntry = {
            title: '',
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
}

