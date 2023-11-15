import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-link-invoice-dialog',
    templateUrl: './link-invoice-dialog.component.html'
})

export class LinkInvoiceDialogComponent extends DialogComponent {
    @Input() liIds: number[] = [];
    @Input() poId: number = null;

    provider: ComboboxEntry;
    invoice: ComboboxEntry;

    constructor(private modal: NgbModal) { super(modal); }
}
