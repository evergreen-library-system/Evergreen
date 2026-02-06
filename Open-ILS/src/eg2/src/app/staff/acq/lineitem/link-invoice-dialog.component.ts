import {Component, Input} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-link-invoice-dialog',
    templateUrl: './link-invoice-dialog.component.html',
    imports: [
        ComboboxComponent,
        CommonModule,
        FormsModule
    ]
})

export class LinkInvoiceDialogComponent extends DialogComponent {
    @Input() liIds: number[] = [];
    @Input() poId: number = null;

    provider: ComboboxEntry;
    invoice: ComboboxEntry;

    constructor(private modal: NgbModal) { super(modal); }
}
