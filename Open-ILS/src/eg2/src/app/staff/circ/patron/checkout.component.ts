import {Component, OnInit, AfterViewInit, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Observable, empty, of} from 'rxjs';
import {tap, switchMap} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronManagerService} from './patron.service';
import {CheckoutParams, CheckoutResult, CircService} from '@eg/staff/share/circ/circ.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';

@Component({
  templateUrl: 'checkout.component.html',
  selector: 'eg-patron-checkout'
})
export class CheckoutComponent implements OnInit {

    maxNoncats = 99; // Matches AngJS version
    checkoutNoncat: IdlObject = null;

    @ViewChild('nonCatCount') nonCatCount: PromptDialogComponent;

    constructor(
        private org: OrgService,
        private net: NetService,
        public circ: CircService,
        public patronService: PatronService,
        public context: PatronManagerService
    ) {}

    ngOnInit() {
        this.circ.getNonCatTypes();
    }

    ngAfterViewInit() {
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
        }

        return null;
    }

    checkout() {
        this.collectParams()

        .then((params: CheckoutParams) => {
            if (!params) { return null; }
            return this.circ.checkout(params);
        })

        .then((result: CheckoutResult) => {
            if (!result) { return null; }

            // Reset the form
            this.checkoutNoncat = null;
        });
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

