import { Component, Input, OnInit, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {InvoiceService} from '../invoice/invoice.service';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-add-extra-items-for-order-dialog',
    templateUrl: './add-extra-items-for-order-dialog.component.html',
    imports: [
        ComboboxComponent,
        CommonModule,
        FormsModule
    ]
})

export class AddExtraItemsForOrderDialogComponent extends DialogComponent implements OnInit {
    private modal: NgbModal;
    private invoiceService = inject(InvoiceService);


    @Input() extra_count: number;
    @Input() owners: number[];
    @Input() perCopyPrice: number;
    fund: ComboboxEntry;
    fundSummary: any = {};

    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }

    ngOnInit() {
        console.debug('AddExtraItemsForOrderDialogComponent, this', this, this.modal);
    }

    async fundSelected(event: any) {
        console.debug('AddExtraItemsForOrderDialogComponent, fundSelected(), event', event);
        this.fundSummary = await this.invoiceService.getFundSummary(event.id);
        console.debug('AddExtraItemsForOrderDialogComponent, fundSummary', this.fundSummary);
    }
}
