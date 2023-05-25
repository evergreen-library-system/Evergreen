import {Component, Input} from '@angular/core';
import {OnInit} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PoService} from './po.service';

@Component({
    templateUrl: 'label.component.html',
    selector: 'eg-po-label'
})
export class PoLabelComponent implements OnInit {

    @Input() po: IdlObject;
    @Input() poId: number;
    @Input() showEstimatedCost = false;

    constructor(
        private idl: IdlService,
        private poService: PoService,
    ) {}

    async ngOnInit() {
        console.debug('PoLabelComponent, poId, po, this',this.poId,this.po,this);
        if (this.poId) {
            this.poId = this.idl.pkeyValue( this.poId );
            console.debug('PoLabelComponent, pkeyValue poId',this.poId);
        }
        if (this.po && !this.po?.amount_estimated()) {
            this.poId = this.po?.id(); // needs more fleshing
        }
        if (this.poId) {
            try {
                this.po = await this.poService.getFleshedPo(this.poId);
            } catch(E) {
                console.error('PoLabel: Problem retrieving purchase order',E);
            }
        }
        // console.log('PoLabel, po #' + this.po.id(),this.po);
        // console.log('PoLabel, po.amount_estimated()',this.po.amount_estimated());
    }

    /* from the Angular implementation, for lineitems:
     *
     *   <a class="label-with-material-icon"
     *      title="Purchase Order" i18n-title
     *      routerLink="/staff/acq/po/{{li.purchase_order().id()}}">
     *     <span class="material-icons small me-1" aria-hidden="true">center_focus_weak</span>
     *     <span i18n>{{li.purchase_order().name()}}</span>
     *   </a>
     *
     */

    /* from the Dojo implementation, for invoice items:
     *
     *  var po_label = dojo.string.substitute(
     *      localeStrings.INVOICE_ITEM_PO_LABEL,
     *      [ oilsBasePath, po2.id(), po2.name(),
     *        orderDate, po2.amount_estimated().toFixed(2)
     *      ]
     *  );
     *
     * INVOICE_ITEM_PO_LABEL = "<a target='_top' href='/eg2/en-US/staff/acq/po/${1}'>PO #${2} ${3}</a><br/>Total Estimated Cost: $${4}"
     *
     * And for lineitems:
     *
     * <a style='padding-right: 10px;' class='hidden${20}' * target='_top'
     *                                                20 = a classname toggle if a po exists
     *  href='/eg2/en-US/staff/acq/po/${12}#${10}'>&#x2318; ${13} ${18}</a>
     *                                  12 = po id
     *                                        10 = lineitem id
     *                                                        13 = po name
     *                                                              18 = order date
     *
     */

}

