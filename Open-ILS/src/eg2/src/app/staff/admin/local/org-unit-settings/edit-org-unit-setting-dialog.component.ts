import {Component} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-admin-edit-org-unit-setting-dialog',
    templateUrl: './edit-org-unit-setting-dialog.component.html'
})

export class EditOuSettingDialogComponent extends DialogComponent {

    // What OU Setting we're editing
    entry: any = {};
    entryValue: any;
    entryContext: IdlObject;
    linkedFieldOptions: IdlObject[];

    constructor(
        private modal: NgbModal
    ) {
        super(modal);
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


