import {Component, Input} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-claim-policy-dialog',
    templateUrl: './claim-policy-dialog.component.html',
    imports: [
        ComboboxComponent,
        CommonModule,
        FormsModule,
    ]
})

export class ClaimPolicyDialogComponent extends DialogComponent {
    @Input() ids: number[];
    claimPolicy: number;
    constructor(private modal: NgbModal) { super(modal); }
}
