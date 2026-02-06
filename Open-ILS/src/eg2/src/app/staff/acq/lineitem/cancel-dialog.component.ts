import {Component, Input} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { CommonModule } from '@angular/common';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';
import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-cancel-dialog',
    templateUrl: './cancel-dialog.component.html',
    imports: [
        ComboboxComponent,
        CommonModule,
        FormsModule
    ]
})

export class CancelDialogComponent extends DialogComponent {
    @Input() recordType = 'po';
    cancelReason: number;
    constructor(private modal: NgbModal) { super(modal); }
}


