import {Component, OnInit, Input, Output} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';

@Component({
  templateUrl: 'order-summary.component.html',
  selector: 'eg-lineitem-order-summary'
})
export class LineitemOrderSummaryComponent {
    @Input() li: IdlObject;

    // True if at least one item has been invoiced and all items are either
    // invoiced or canceled.
    paidOff(): boolean {
        const sum = this.li.order_summary();
        return (
            sum.invoice_count() > 0 && (
                sum.item_count() === (sum.invoice_count() + sum.cancel_count())
            )
        );
    }
}

