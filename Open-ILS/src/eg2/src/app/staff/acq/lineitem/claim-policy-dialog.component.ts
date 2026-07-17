import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

import { FormsModule } from '@angular/forms';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-claim-policy-dialog',
    templateUrl: './claim-policy-dialog.component.html',
    imports: [
        ComboboxComponent,
        FormsModule
    ]
})

export class ClaimPolicyDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() ids: number[];
    claimPolicy: number;
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}
