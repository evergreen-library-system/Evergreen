import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {PoService} from './po.service';

@Component({
  templateUrl: 'charges.component.html',
  selector: 'eg-acq-po-charges'
})
export class PoChargesComponent implements OnInit {

    showBody = false;
    autoId = -1;

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        public  poService: PoService
    ) {}

    ngOnInit() {
        if (this.po()) {
            // Sometimes our PO is already available at render time.
             if (this.po().po_items().length > 0) {
                this.showBody = true;
            }
        }

        // Other times we have to wait for it.
        this.poService.poRetrieved.subscribe(() => {
            if (this.po().po_items().length > 0) {
                this.showBody = true;
            }
        });
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
        if (!charge.inv_item_type()) { return; }

        charge.id(undefined);
        this.pcrud.create(charge).toPromise()
        .then(item => {
            charge.id(item.id());
            charge.isnew(false);
        })
        .then(_ => this.poService.refreshOrderSummary());
    }

    removeCharge(charge: IdlObject) {
        this.po().po_items( // remove local copy
            this.po().po_items().filter(item => item.id() !== charge.id())
        );

        if (!charge.isnew()) {
            this.pcrud.remove(charge).toPromise()
            .then(_ => this.poService.refreshOrderSummary());
        }
    }
}

