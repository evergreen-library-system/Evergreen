import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import { LineitemCopiesComponent } from './copies.component';
import { CommonModule } from '@angular/common';

@Component({
    selector: 'eg-acq-add-copies-dialog',
    templateUrl: './add-copies-dialog.component.html',
    imports: [CommonModule, LineitemCopiesComponent]
})

export class AddCopiesDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() ids: number[];
    lineitemWithCopies: IdlObject;
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}


