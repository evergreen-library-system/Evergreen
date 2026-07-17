import { Component, inject } from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { StaffCommonModule } from '@eg/staff/common.module';

/** Bad Item Barcode Dialog */

@Component({
    templateUrl: 'bad-barcode-dialog.component.html',
    selector: 'eg-bad-barcode-dialog',
    imports: [StaffCommonModule]
})
export class BadBarcodeDialogComponent extends DialogComponent {
    private modal: NgbModal;


    barcode: string;

    constructor() {
        const modal = inject(NgbModal);

        super(modal);

        this.modal = modal;
    }
}


