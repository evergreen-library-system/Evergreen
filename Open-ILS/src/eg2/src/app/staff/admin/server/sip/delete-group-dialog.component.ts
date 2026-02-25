import { Component, Input, OnInit, inject } from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import { CommonModule } from '@angular/common';

@Component({
    templateUrl: './delete-group-dialog.component.html',
    selector: 'eg-sip-group-delete-dialog',
    imports: [
        ComboboxComponent,
        CommonModule
    ]
})
export class DeleteGroupDialogComponent extends DialogComponent implements OnInit {
    private modal: NgbModal;
    private auth = inject(AuthService);
    private net = inject(NetService);


    @Input() group: IdlObject;
    @Input() settingGroups: ComboboxEntry[];
    targetGroup = 1;  // Default to the 'Default Settings' group.
    trimmedSettingGroups: ComboboxEntry[];

    constructor() {
        const modal = inject(NgbModal);

        super(modal);

        this.modal = modal;
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

