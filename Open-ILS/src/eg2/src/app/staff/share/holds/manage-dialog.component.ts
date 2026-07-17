import { Component, OnInit, Input, inject } from '@angular/core';
import {Observable} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

import { HoldManageComponent } from './manage.component';

/**
 * Dialog wrapper for ManageHoldsComponent.
 */

@Component({
    selector: 'eg-hold-manage-dialog',
    templateUrl: 'manage-dialog.component.html',
    imports: [
        HoldManageComponent
    ]
})

export class HoldManageDialogComponent
    extends DialogComponent implements OnInit {
    private modal: NgbModal;


    @Input() holdIds: number[];

    constructor() {
        const modal = inject(NgbModal);
        // required for passing to parent
        super(modal); // required for subclassing

        this.modal = modal;
    }

    open(args: NgbModalOptions): Observable<boolean> {
        return super.open(args);
    }

    onComplete(changesMade: boolean) {
        this.close(changesMade);
    }
}



