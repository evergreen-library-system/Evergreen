import {Component, Input, OnInit} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    templateUrl: './delete-group-dialog.component.html',
    selector: 'eg-sip-group-delete-dialog'
})
export class DeleteGroupDialogComponent extends DialogComponent implements OnInit {

    @Input() group: IdlObject;
    @Input() settingGroups: ComboboxEntry[];
    targetGroup = 1;  // Default to the 'Default Settings' group.
    trimmedSettingGroups: ComboboxEntry[];

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private net: NetService
    ) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.trimmedSettingGroups = this.settingGroups.filter(
                entry => entry.id !== this.group.id());
        });
    }

    grpChanged(entry: ComboboxEntry) {
        if (entry) {
            this.targetGroup = entry.id;
        }
    }

    doDelete() {
        this.net.request('open-ils.sip2',
            'open-ils.sip2.setting_group.delete',
            this.auth.token(), this.group.id(), this.targetGroup
        ).subscribe(ok => this.close((Number(ok) === 1)));
    }
}

