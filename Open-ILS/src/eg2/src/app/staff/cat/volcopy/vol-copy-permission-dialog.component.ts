import { Component, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    selector: 'eg-vol-copy-permission-dialog',
    templateUrl: './vol-copy-permission-dialog.component.html',
    imports: [StaffCommonModule]
})

export class VolCopyPermissionDialogComponent extends DialogComponent {
    private modal: NgbModal;

    dispatch: string;
    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }
}


