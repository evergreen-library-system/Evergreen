import {Component, Input} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-add-to-po-dialog',
    templateUrl: './add-to-po-dialog.component.html',
    imports: [
        ComboboxComponent,
        CommonModule,
        FormsModule
    ]
})

export class AddToPoDialogComponent extends DialogComponent {
    @Input() ids: number[];
    po: ComboboxEntry;
    constructor(private modal: NgbModal) { super(modal); }
}


