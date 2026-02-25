import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-disencumber-charge-dialog',
    templateUrl: './disencumber-charge-dialog.component.html',
    imports: [ComboboxComponent]
})

export class DisencumberChargeDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() charge: IdlObject;
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}


