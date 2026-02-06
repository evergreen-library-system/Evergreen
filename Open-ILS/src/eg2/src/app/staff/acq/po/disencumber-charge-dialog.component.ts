import {Component, Input} from '@angular/core';
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
    @Input() charge: IdlObject;
    constructor(private modal: NgbModal) { super(modal); }
}


