import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {switchMap} from 'rxjs/operators';
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
import {CircService} from './circ.service';

/* Add a billing to a transaction */

const DEFAULT_BILLING_TYPE = 101; // Stock "Misc"

@Component({
  selector: 'eg-add-billing-dialog',
  templateUrl: 'billing-dialog.component.html'
})

export class AddBillingDialogComponent
    extends DialogComponent implements OnInit {

    @Input() xactId: number;

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
        private circ: CircService,
        private org: OrgService,
        private auth: AuthService) {
        super(modal);
    }

    ngOnInit() {
        this.circ.getBillingTypes().then(types => {
            this.billingTypes = types.map(bt => {
                return {id: bt.id(), label: bt.name(), fm: bt};
            });
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

        // Fetch the xact data before opening the dialog.
        return this.pcrud.retrieve('mbt', this.xactId, {
            flesh: 2,
            flesh_fields: {
                mbt: ['usr', 'summary', 'circulation'],
                au: ['card']
            }
        }).pipe(switchMap(xact => {
            this.xact = xact;
            return super.open(options);
        }));
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
        const bill = this.idl.create('mb');
        bill.xact(this.xactId);
        bill.amount(this.amount);
        bill.btype(this.billingType.id);
        bill.billing_type(this.billingType.label);
        bill.note(this.note);

        this.net.request(
            'open-ils.circ',
            'open-ils.circ.money.billing.create',
            this.auth.token(), bill
        ).subscribe(billId => {

            const evt = this.evt.parse(billId);
            if (evt) {
                console.error(evt);
                alert(evt);
                this.close(null);
            } else {
                this.close(billId);
            }
        });
    }
}

