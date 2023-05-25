import {Component, Input, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {InvoiceService} from '../invoice/invoice.service';

@Component({
    selector: 'eg-acq-add-extra-items-for-order-dialog',
    templateUrl: './add-extra-items-for-order-dialog.component.html'
})

export class AddExtraItemsForOrderDialogComponent extends DialogComponent implements OnInit {

    @Input() extra_count: number;
    @Input() owners: number[];
    @Input() perCopyPrice: number;
    fund: ComboboxEntry;
    fundSummary: any = {};

    constructor(
        private modal: NgbModal,
        private invoiceService: InvoiceService,
    ) { super(modal); }

    ngOnInit() {
        console.debug('AddExtraItemsForOrderDialogComponent, this', this, this.modal);
    }

    async fundSelected(event: any) {
        console.debug('AddExtraItemsForOrderDialogComponent, fundSelected(), event', event);
        this.fundSummary = await this.invoiceService.getFundSummary(event.id);
        console.debug('AddExtraItemsForOrderDialogComponent, fundSummary', this.fundSummary);
    }
}
