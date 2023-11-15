import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-delete-lineitems-dialog',
    templateUrl: './delete-lineitems-dialog.component.html'
})

export class DeleteLineitemsDialogComponent extends DialogComponent {
    @Input() ids: number[];
    constructor(private modal: NgbModal) { super(modal); }
}


