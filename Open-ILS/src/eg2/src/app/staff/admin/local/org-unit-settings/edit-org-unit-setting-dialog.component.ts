import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {OrgUnitSetting} from '@eg/staff/admin/local/org-unit-settings/org-unit-settings.component';

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
        private auth: AuthService,
        private net: NetService,
        private org: OrgService,
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
        return this.entry.dataType;
    }

    setInputValue(inputValue) {
        console.log("In Input value");
        console.log(inputValue);
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


