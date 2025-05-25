import {Component} from '@angular/core';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {CheckinResult} from './circ.service';

/** Route Item Dialog */

@Component({
    templateUrl: 'in-transit-dialog.component.html',
    selector: 'eg-copy-in-transit-dialog'
})
export class CopyInTransitDialogComponent extends DialogComponent {

    checkout: CheckinResult;

    constructor(private modal: NgbModal) {
        super(modal);
    }
}


