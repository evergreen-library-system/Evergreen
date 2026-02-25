import { Component, Input, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { CommonModule } from '@angular/common';

@Component({
    selector: 'eg-acq-delete-lineitems-dialog',
    templateUrl: './delete-lineitems-dialog.component.html',
    imports: [CommonModule]
})

export class DeleteLineitemsDialogComponent extends DialogComponent {
    private modal: NgbModal;

    @Input() ids: number[];
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}


