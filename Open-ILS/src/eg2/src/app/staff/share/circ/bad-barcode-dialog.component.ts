import {Component} from '@angular/core';
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

    barcode: string;

    constructor(private modal: NgbModal) {
        super(modal);
    }
}


