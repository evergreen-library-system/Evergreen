import { Component, Input, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-admin-ou-setting-json-dialog',
    templateUrl: './org-unit-setting-json-dialog.component.html',
    imports: [StaffCommonModule]
})

export class OuSettingJsonDialogComponent extends DialogComponent {
    private modal: NgbModal;


    isExport: boolean;
    @Input() jsonData: string;

    constructor() {
        const modal = inject(NgbModal);

        super(modal);

        this.modal = modal;
    }

    update() {
        this.close({
            apply: true,
            jsonData: this.jsonData
        });
    }
}
