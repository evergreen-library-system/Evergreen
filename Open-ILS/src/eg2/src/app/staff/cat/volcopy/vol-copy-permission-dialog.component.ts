import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-vol-copy-permission-dialog',
    templateUrl: './vol-copy-permission-dialog.component.html'
})

export class VolCopyPermissionDialogComponent extends DialogComponent {
    dispatch: string;
    constructor(private modal: NgbModal) { super(modal); }
}


