import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

import { ComboboxComponent } from '@eg/share/combobox/combobox.component';
import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-cancel-dialog',
    templateUrl: './cancel-dialog.component.html',
    imports: [
        ComboboxComponent,
        FormsModule
    ]
})

export class CancelDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() recordType = 'po';
    cancelReason: number;
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}


