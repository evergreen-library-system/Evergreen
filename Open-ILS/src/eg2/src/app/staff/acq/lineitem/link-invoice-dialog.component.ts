import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';

import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-link-invoice-dialog',
    templateUrl: './link-invoice-dialog.component.html',
    imports: [
        ComboboxComponent,
        FormsModule
    ]
})

export class LinkInvoiceDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() liIds: number[] = [];
    @Input() poId: number = null;

    provider: ComboboxEntry;
    invoice: ComboboxEntry;

    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}
