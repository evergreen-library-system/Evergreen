import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

import { FormsModule } from '@angular/forms';

@Component({
    selector: 'eg-acq-export-attributes-dialog',
    templateUrl: './export-attributes-dialog.component.html',
    imports: [FormsModule]
})

export class ExportAttributesDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() ids: number[];
    selectedAttr = 'isbn';
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}


