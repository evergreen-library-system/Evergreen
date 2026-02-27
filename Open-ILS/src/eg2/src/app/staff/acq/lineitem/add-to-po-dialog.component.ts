import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';

import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-add-to-po-dialog',
    templateUrl: './add-to-po-dialog.component.html',
    imports: [
        ComboboxComponent,
        FormsModule
    ]
})

export class AddToPoDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() ids: number[];
    po: ComboboxEntry;
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}


