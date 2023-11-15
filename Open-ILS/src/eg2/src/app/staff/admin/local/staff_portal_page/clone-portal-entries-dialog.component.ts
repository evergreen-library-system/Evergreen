import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgForm, NG_VALIDATORS} from '@angular/forms';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-clone-portal-entries-dialog',
    templateUrl: './clone-portal-entries-dialog.component.html'
})

export class ClonePortalEntriesDialogComponent
    extends DialogComponent implements OnInit {

    result = { };

    constructor(
        private modal: NgbModal
    ) {
        super(modal);
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
