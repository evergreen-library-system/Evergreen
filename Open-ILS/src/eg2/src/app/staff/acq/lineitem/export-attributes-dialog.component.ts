import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-export-attributes-dialog',
    templateUrl: './export-attributes-dialog.component.html'
})

export class ExportAttributesDialogComponent extends DialogComponent {
    @Input() ids: number[];
    selectedAttr = 'isbn';
    constructor(private modal: NgbModal) { super(modal); }
}


