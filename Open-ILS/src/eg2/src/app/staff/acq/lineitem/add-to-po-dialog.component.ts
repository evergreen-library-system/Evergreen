import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-add-to-po-dialog',
    templateUrl: './add-to-po-dialog.component.html'
})

export class AddToPoDialogComponent extends DialogComponent {
    @Input() ids: number[];
    po: ComboboxEntry;
    constructor(private modal: NgbModal) { super(modal); }
}


