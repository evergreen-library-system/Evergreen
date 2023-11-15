import {Component, Input} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-admin-ou-setting-json-dialog',
    templateUrl: './org-unit-setting-json-dialog.component.html'
})

export class OuSettingJsonDialogComponent extends DialogComponent {

    isExport: boolean;
    @Input() jsonData: string;

    constructor(
        private modal: NgbModal
    ) {
        super(modal);
    }

    update() {
        this.close({
            apply: true,
            jsonData: this.jsonData
        });
    }
}
