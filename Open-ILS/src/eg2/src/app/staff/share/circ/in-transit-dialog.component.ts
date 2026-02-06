import {Component} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {CheckinResult} from './circ.service';
import { StaffCommonModule } from '@eg/staff/common.module';

/** Route Item Dialog */

@Component({
    templateUrl: 'in-transit-dialog.component.html',
    selector: 'eg-copy-in-transit-dialog',
    imports: [StaffCommonModule]
})
export class CopyInTransitDialogComponent extends DialogComponent {

    checkout: CheckinResult;

    constructor(private modal: NgbModal) {
        super(modal);
    }
}


