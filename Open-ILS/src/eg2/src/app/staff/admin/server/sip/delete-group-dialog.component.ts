import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Observable, of} from 'rxjs';
import {map, tap, switchMap, catchError} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';
import {NgbModal, NgbModalRef, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';

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

