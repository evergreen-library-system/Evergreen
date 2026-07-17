import { Component, OnInit, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-clone-portal-entries-dialog',
    templateUrl: './clone-portal-entries-dialog.component.html',
    imports: [StaffCommonModule]
})

export class ClonePortalEntriesDialogComponent
    extends DialogComponent implements OnInit {
    private modal: NgbModal;


    result = { };

    constructor() {
        const modal = inject(NgbModal);

        super(modal);

        this.modal = modal;
    }

    ngOnInit() {
        this.onOpen$.subscribe(() => this._initRecord());
    }

    private _initRecord() {
        this.result = {
            source_library: null,
            target_library: null,
            overwrite_target: false
        };
    }

}
