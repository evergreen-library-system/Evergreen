import { Component, ViewChild, OnInit, inject } from '@angular/core';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';
import {IdlObject} from '@eg/core/idl.service';
import {GridCellTextGenerator} from '@eg/share/grid/grid';
import {StringComponent} from '@eg/share/string/string.component';
import {ClonePortalEntriesDialogComponent} from './clone-portal-entries-dialog.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {merge, EMPTY} from 'rxjs';
import { StaffCommonModule } from '@eg/staff/common.module';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';
import { TranslateComponent } from '@eg/share/translate/translate.component';
import { OrgFamilySelectComponent } from '@eg/share/org-family-select/org-family-select.component';

@Component({
    templateUrl: './staff-portal-page.component.html',
    imports: [
        StaffCommonModule,
        ClonePortalEntriesDialogComponent,
        FmRecordEditorComponent,
        TranslateComponent,
        OrgFamilySelectComponent
    ]
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
            { next: entry => {
                if (entry.owner() === tgt) {
                    entry.isdeleted(true);
                } else {
                    entry.owner(tgt);
                    entry.id(null);
                    entry.isnew(true);
                }
                updates.push(entry);
            }, error: (err: unknown) => {} },
        ).add(() => {
            this.pcrud.autoApply(updates).subscribe(
                { next: val => {}, error: (err: unknown) => {
                    this.cloneFailedString.current()
                        .then(str => this.toast.danger(str));
                }, complete: () => {
                    this.cloneSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.searchOrgs = {primaryOrgId: tgt}; // change the org filter to the
                    // the one we just cloned into
                    this.grid.reload();
                } }
            );
        });
    }
}
