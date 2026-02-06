import {Component, Input} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { CommonModule } from '@angular/common';

@Component({
    selector: 'eg-acq-delete-lineitems-dialog',
    templateUrl: './delete-lineitems-dialog.component.html',
    imports: [CommonModule]
})

export class DeleteLineitemsDialogComponent extends DialogComponent {
    @Input() ids: number[];
    constructor(private modal: NgbModal) { super(modal); }
}


