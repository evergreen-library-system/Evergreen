import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, switchMap, tap} from 'rxjs';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {BillingService} from './billing.service';

/* Add a billing to a transaction */

const DEFAULT_BILLING_TYPE = 101; // Stock "Misc"

@Component({
    selector: 'eg-add-billing-dialog',
    templateUrl: 'billing-dialog.component.html'
})

export class AddBillingDialogComponent
    extends DialogComponent implements OnInit {

    @Input() xactId: number;
    @Input() newXact = false;
    @Input() patronId: number;

    patron: IdlObject;
    xact: IdlObject;
    billingType: ComboboxEntry;
    billingTypes: ComboboxEntry[] = [];
    hereOrg: string;
    amount: number;
    note: string;

    @ViewChild('successMsg') private successMsg: StringComponent;
    @ViewChild('errorMsg') private errorMsg: StringComponent;
    @ViewChild('bTypeCbox') private bTypeCbox: ComboboxComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private evt: EventService,
        private pcrud: PcrudService,
        private billing: BillingService,
        private org: OrgService,
        private auth: AuthService) {
        super(modal);
    }

    ngOnInit() {
        this.billing.getUserBillingTypes().then(types => {
            this.billingTypes = types.map(bt => {
                return {id: bt.id(), label: bt.name(), fm: bt};
            });
            this.billingType = this.billingTypes
                .filter(t => t.id === DEFAULT_BILLING_TYPE)[0];
        });

        this.hereOrg = this.org.get(this.auth.user().ws_ou()).shortname();

        this.onOpen$.subscribe(_ => {
            this.amount = null;
            this.note = '';
            this.bTypeCbox.selectedId = DEFAULT_BILLING_TYPE;
            const node = document.getElementById('amount-input');
            if (node) { node.focus(); }
        });
    }

    open(options: NgbModalOptions = {}): Observable<any> {
        let obs: Observable<any>;

        // Load some data before opening.
        if (this.newXact) {

            obs = this.pcrud.retrieve('au', this.patronId,
                {flesh: 1, flesh_fields: {au: ['card']}}
            ).pipe(tap(user => this.patron = user));

        } else {

            obs = this.pcrud.retrieve('mbt', this.xactId, {
                flesh: 2,
                flesh_fields: {
                    mbt: ['usr', 'summary', 'circulation'],
                    au: ['card']
                }
            }).pipe(tap(xact => {
                this.xact = xact;
                this.patron = xact.usr();
            }));
        }

        return obs.pipe(switchMap(_ => super.open(options)));
    }

    isRenewal(): boolean {
        return (
            this.xact &&
            this.xact.circulation() &&
            this.xact.circulation().parent_circ() !== null
        );
    }

    btChanged(entry: ComboboxEntry) {
        this.billingType = entry;
        if (entry && entry.fm.default_price()) {
            this.amount = entry.fm.default_price();
        }
    }

    saveable(): boolean {
        return this.billingType && this.amount > 0;
    }

    submit() {
        const promise = this.newXact ?
            this.createGroceryXact() : Promise.resolve(this.xactId);

        let xactId;
        promise.then(id => {
            xactId = id;
            return this.createBill(id);
        })
            .then(billId => this.close({xactId: xactId, billId: billId}));
    }

    handleResponse(id: number): number {
        const evt = this.evt.parse(id);
        if (evt) {
            console.error(evt);
            alert(evt);
            return null;
        } else {
            return id;
        }
    }

    createGroceryXact(): Promise<number> {
        const groc = this.idl.create('mg');
        groc.billing_location(this.auth.user().ws_ou());
        groc.note(this.note);
        groc.usr(this.patronId);

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.money.grocery.create',
            this.auth.token(), groc
        ).toPromise().then(xactId => this.handleResponse(xactId));
    }

    createBill(xactId: number): Promise<number> {
        if (!xactId) { return Promise.reject('no xact'); }

        const bill = this.idl.create('mb');
        bill.xact(xactId);
        bill.amount(this.amount);
        bill.btype(this.billingType.id);
        bill.billing_type(this.billingType.label);
        bill.note(this.note);

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.money.billing.create',
            this.auth.token(), bill
        ).toPromise().then(billId => this.handleResponse(billId));
    }
}

