import { Component, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { TimezoneSelectComponent } from './timezone-select/timezone-select.component';
import { OrgSelectComponent } from '@eg/share/org-select/org-select.component';
import { FormsModule } from '@angular/forms';
import { CommonModule } from '@angular/common';

@Component({
    selector: 'eg-admin-edit-org-unit-setting-dialog',
    templateUrl: './edit-org-unit-setting-dialog.component.html',
    imports: [
        CommonModule,
        FormsModule,
        OrgSelectComponent,
        TimezoneSelectComponent
    ]
})

export class EditOuSettingDialogComponent extends DialogComponent {
    private modal: NgbModal;


    // What OU Setting we're editing
    entry: any = {};
    entryValue: any;
    entryContext: IdlObject;
    linkedFieldOptions: IdlObject[];

    constructor() {
        const modal = inject(NgbModal);

        super(modal);
        this.modal = modal;

        if (!this.entry) {
            this.entryValue = null;
            this.entryContext = null;
            this.linkedFieldOptions = null;
        }
    }

    inputType() {
        if (this.entry.name === 'lib.timezone') {
            return 'timezone';
        }
        return this.entry.dataType;
    }

    setInputValue(inputValue) {
        this.entryValue = inputValue;
    }

    getFieldClass() {
        return this.entry.fm_class;
    }

    delete() {
        this.close({setting: {[this.entry.name]: null}, context: this.entryContext});
    }

    update() {
        this.close({setting: {[this.entry.name]: this.entryValue}, context: this.entryContext});
    }
}


