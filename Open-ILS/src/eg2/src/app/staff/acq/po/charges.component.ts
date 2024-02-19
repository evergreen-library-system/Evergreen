import {Component, OnInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {Subscription} from 'rxjs';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {PoService} from './po.service';
import {DisencumberChargeDialogComponent} from './disencumber-charge-dialog.component';
import {PermService} from '@eg/core/perm.service';


@Component({
    templateUrl: 'charges.component.html',
    selector: 'eg-acq-po-charges'
})
export class PoChargesComponent implements OnInit, OnDestroy {

    showBody = false;
    canModify = false;
    autoId = -1;
    poSubscription: Subscription;
    owners: number[] = [];

    @ViewChild('disencumberChargeDialog') disencumberChargeDialog: DisencumberChargeDialogComponent;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private evt: EventService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private org: OrgService,
        public  poService: PoService,
        private perm: PermService
    ) {}

    ngOnInit() {
        if (this.po()) {
            // Sometimes our PO is already available at render time.
            this.showBody = this.po().po_items().length > 0;
            this.canModify = this.po().order_date() ? false : true;
        }

        // Other times we have to wait for it.
        this.poSubscription = this.poService.poRetrieved.subscribe(() => {
            this.showBody = this.po().po_items().length > 0;
            this.canModify = this.po().order_date() ? false : true;
        });

        this.perm.hasWorkPermAt(['MANAGE_FUND','CREATE_PURCHASE_ORDER'],true).then((perm) => {
            this.owners.concat(perm['MANAGE_FUND']);

            perm['CREATE_PURCHASE_ORDER'].forEach(ou => {
                if(!this.owners.includes(ou)) {
                    this.owners.push(ou);
                }
            });
        });
    }

    ngOnDestroy() {
        if (this.poSubscription) {
            this.poSubscription.unsubscribe();
        }
    }

    po(): IdlObject {
        return this.poService.currentPo;
    }

    newCharge() {
        this.showBody = true;
        const chg = this.idl.create('acqpoi');
        chg.isnew(true);
        chg.purchase_order(this.po().id());
        chg.id(this.autoId--);
        this.po().po_items().push(chg);
    }

    saveCharge(charge: IdlObject) {
        if (!charge.inv_item_type() || !charge.fund()) { return; }
        if (typeof charge.estimated_cost() !== 'number') { return; }

        if (charge.isnew()) {
            charge.id(undefined);
            this.pcrud.create(charge).toPromise()
                .then(item => {
                    charge.id(item.id());
                    charge.isnew(false);
                })
                .then(_ => this.poService.refreshOrderSummary());
        } else if (charge.ischanged()) {
            this.pcrud.update(charge).toPromise()
                .then(item => {
                    charge.ischanged(false);
                })
                .then(_ => this.poService.refreshOrderSummary());
        }
    }

    canDisencumber(charge: IdlObject): boolean {
        if (!this.po() || !this.po().order_date() || this.po().state() === 'cancelled') {
            return false; // order must be loaded, activated, and not cancelled
        }
        if (!charge.fund_debit()) {
            return false; // that which is not encumbered cannot be disencumbered
        }

        const debit = charge.fund_debit();
        if (debit.encumbrance() === 'f') {
            return false; // that which is expended cannot be disencumbered
        }
        if (debit.invoice_entry()) {
            // we shouldn't actually be a po_item that is
            // linked to an invoice_entry, but if we are,
            // do NOT touch
            return false;
        }
        if (debit.invoice_items() && debit.invoice_items().length) {
            // we're linked to an invoice item, so the disposition of the
            // invoice entry should govern things
            return false;
        }
        if (Number(debit.amount()) === 0) {
            return false; // we're already at zero
        }
        return true; // we're likely OK to disencumber
    }

    canDelete(charge: IdlObject): boolean {
        if (!this.po()) {
            return false;
        }

        const debit = charge.fund_debit();
        if (debit && debit.encumbrance() === 'f') {
            return false; // if it's expended, we can't just delete it
        }
        if (debit && debit.invoice_entry()) {
            return false; // we shouldn't actually be a po_item that is
            // linked to an invoice_entry, but if we are,
            // do NOT touch
        }
        if (debit && debit.invoice_items() && debit.invoice_items().length) {
            // we're linked to an invoice item, so the disposition of the
            // invoice entry should govern things
            return false;
        }
        return true; // we're likely OK to delete
    }

    disencumberCharge(charge: IdlObject) {
        this.disencumberChargeDialog.charge = charge;
        this.disencumberChargeDialog.open().subscribe(doIt => {
            if (!doIt) { return; }

            return this.net.request(
                'open-ils.acq',
                'open-ils.acq.po_item.disencumber',
                this.auth.token(), charge.id()
            ).toPromise().then(res => {
                const evt = this.evt.parse(res);
                if (evt) { return Promise.reject(evt + ''); }
            }).then(_ => this.poService.refreshOrderSummary(true));
        });
    }

    removeCharge(charge: IdlObject) {
        this.po().po_items( // remove local copy
            this.po().po_items().filter(item => item.id() !== charge.id())
        );

        if (!charge.isnew()) {
            return this.net.request(
                'open-ils.acq',
                'open-ils.acq.po_item.delete',
                this.auth.token(), charge.id()
            ).toPromise().then(res => {
                const evt = this.evt.parse(res);
                if (evt) { return Promise.reject(evt + ''); }
            }).then(_ => this.poService.refreshOrderSummary(true));
        }
    }
}

