import {Component, OnInit, Input} from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {CreditCardPaymentParams} from './billing.service';

/* Dialog for collecting credit card payment information */

@Component({
    selector: 'eg-credit-card-dialog',
    templateUrl: 'credit-card-dialog.component.html'
})

export class CreditCardDialogComponent
    extends DialogComponent implements OnInit {

    @Input() patron: IdlObject; // au, fleshed with billing address
    args: CreditCardPaymentParams;
    supportsExternal: boolean;
    thisYear = new Date().getFullYear();

    constructor(
        private modal: NgbModal,
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private evt: EventService,
        private pcrud: PcrudService,
        private org: OrgService,
        private serverStore: ServerStoreService,
        private auth: AuthService) {
        super(modal);
    }

    ngOnInit() {

        this.onOpen$.subscribe(_ => {

            this.args = {
                billing_first: this.patron.first_given_name(),
                billing_last: this.patron.family_name(),
            };

            const addr =
                this.patron.billing_address() || this.patron.mailing_address();

            if (addr) {
                this.args.billing_address = addr.street1() +
                    (addr.street2() ? ' ' + addr.street2() : '');
                this.args.billing_city = addr.city();
                this.args.billing_state = addr.state();
                this.args.billing_zip = addr.post_code();
            }

            this.supportsExternal = false;

            this.serverStore.getItem('credit.processor.default')
                .then(processor => {
                    if (processor && processor !== 'Stripe') {
                        this.supportsExternal = true;
                        this.args.where_process = 1;
                    } else {
                        this.args.where_process = 0;
                    }
                });
        });
    }

    saveable(): boolean {
        if (!this.args) { return false; }

        if (this.args.where_process === 0) {
            return Boolean(this.args.approval_code);
        }

        return Boolean(this.args.expire_month) && Boolean(this.args.expire_year);
    }
}

