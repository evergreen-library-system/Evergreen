import { Component } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import { TimezoneSelectComponent } from './timezone-select/timezone-select.component';
import { OrgSelectComponent } from '@eg/share/org-select/org-select.component';
import { FormsModule } from '@angular/forms';

import { ItemLocationSelectComponent } from '@eg/share/item-location-select/item-location-select.component';
import { ComboboxComponent } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-admin-edit-org-unit-setting-dialog',
    templateUrl: './edit-org-unit-setting-dialog.component.html',
    imports: [
        FormsModule,
        ItemLocationSelectComponent,
        OrgSelectComponent,
        TimezoneSelectComponent,
        ComboboxComponent
    ]
})

export class EditOuSettingDialogComponent extends DialogComponent {
    // What OU Setting we're editing
    entry: any = {};
    entryValue: any = null;
    entryContext: IdlObject = null;
    linkedFieldOptions: IdlObject[] = null;

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


