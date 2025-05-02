import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Location} from '@angular/common';
import {FormatService} from '@eg/core/format.service';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';
import {ActivatedRoute} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {NetService} from '@eg/core/net.service';
import {GridCellTextGenerator} from '@eg/share/grid/grid';
import {StringComponent} from '@eg/share/string/string.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ClonePortalEntriesDialogComponent} from './clone-portal-entries-dialog.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {merge, Observable, EMPTY} from 'rxjs';

@Component({
    templateUrl: './staff-portal-page.component.html'
})

export class AdminStaffPortalPageComponent extends AdminPageComponent implements OnInit {

    idlClass = 'cusppe';
    fieldOrder = 'label,entry_type,target_url,url_newtab,entry_text,image_url,page_col,col_pos,owner,id';
    classLabel: string;

    refreshSelected: (idlThings: IdlObject[]) => void;
    createNew: () => void;
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('refreshString', { static: true }) refreshString: StringComponent;
    @ViewChild('refreshErrString', { static: true }) refreshErrString: StringComponent;
    @ViewChild('cloneSuccessString', { static: true }) cloneSuccessString: StringComponent;
    @ViewChild('cloneFailedString', { static: true }) cloneFailedString: StringComponent;
    @ViewChild('cloneDialog', { static: true}) cloneDialog: ClonePortalEntriesDialogComponent;
    @ViewChild('delConfirm', { static: true }) delConfirm: ConfirmDialogComponent;

    constructor(
        route: ActivatedRoute,
        ngLocation: Location,
        format: FormatService,
        idl: IdlService,
        org: OrgService,
        auth: AuthService,
        pcrud: PcrudService,
        perm: PermService,
        toast: ToastService,
        private net: NetService,
        broadcaster: BroadcastService
    ) {
        super(route, ngLocation, format, idl, org, auth, pcrud, perm, toast, broadcaster);
    }

    ngOnInit() {
        super.ngOnInit();

        this.defaultNewRecord = this.idl.create(this.idlClass);
        this.defaultNewRecord.owner(this.auth.user().ws_ou());
    }

    cloneEntries() {
        this.cloneDialog.open().subscribe(
            result => {
                this._handleClone(result.source_library, result.target_library, result.overwrite_target);
            }
        );
    }

    deleteSelected(idlThings: IdlObject[]) {
        this.delConfirm.open().subscribe(confirmed => {
            if (!confirmed) { return; }
            super.doDelete(idlThings);
        });
    }

    _handleClone(src: number, tgt: number, overwrite: Boolean) {
        const updates: IdlObject[] = [];

        const delObs = (overwrite) ?
            this.pcrud.search('cusppe', { owner: tgt }, {}, {}) :
            EMPTY;
        const newObs = this.pcrud.search('cusppe', { owner: src }, {}, {});
        merge(delObs, newObs).subscribe(
            entry => {
                if (entry.owner() === tgt) {
                    entry.isdeleted(true);
                } else {
                    entry.owner(tgt);
                    entry.id(null);
                    entry.isnew(true);
                }
                updates.push(entry);
            },
            (err: unknown) => {},
        ).add(() => {
            this.pcrud.autoApply(updates).subscribe(
                val => {},
                (err: unknown) => {
                    this.cloneFailedString.current()
                        .then(str => this.toast.danger(str));
                },
                () => {
                    this.cloneSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.searchOrgs = {primaryOrgId: tgt}; // change the org filter to the
                    // the one we just cloned into
                    this.grid.reload();
                }
            );
        });
    }
}
