import {Component, OnInit, Input} from '@angular/core';
import {Observable} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

/**
 * Dialog wrapper for ManageHoldsComponent.
 */

@Component({
  selector: 'eg-hold-manage-dialog',
  templateUrl: 'manage-dialog.component.html'
})

export class HoldManageDialogComponent
    extends DialogComponent implements OnInit {

    @Input() holdIds: number[];

    constructor(
        private modal: NgbModal) { // required for passing to parent
        super(modal); // required for subclassing
    }

    open(args: NgbModalOptions): Observable<boolean> {
        return super.open(args);
    }

    onComplete(changesMade: boolean) {
        this.close(changesMade);
    }
}



