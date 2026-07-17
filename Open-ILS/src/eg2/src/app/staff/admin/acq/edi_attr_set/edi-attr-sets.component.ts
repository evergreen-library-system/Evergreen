import { Component, ViewChild, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {Observable, of, mergeMap} from 'rxjs';
import {StringComponent} from '@eg/share/string/string.component';
import {EdiAttrSetProvidersDialogComponent} from './edi-attr-set-providers-dialog.component';
import {EdiAttrSetEditDialogComponent} from './edi-attr-set-edit-dialog.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';
import { TitleComponent } from '@eg/share/title/title.component';
import { OrgFamilySelectComponent } from '@eg/share/org-family-select/org-family-select.component';
import { TranslateComponent } from '@eg/share/translate/translate.component';
import { GridModule } from '@eg/share/grid/grid.module';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';
import { FormsModule } from '@angular/forms';

@Component({
    templateUrl: './edi-attr-sets.component.html',
    imports: [
        AlertDialogComponent,
        CommonModule,
        ConfirmDialogComponent,
        EdiAttrSetEditDialogComponent,
        EdiAttrSetProvidersDialogComponent,
        FmRecordEditorComponent,
        FormsModule,
        GridModule,
        OrgFamilySelectComponent,
        StaffBannerComponent,
        StringComponent,
        TitleComponent,
        TranslateComponent,
    ]
})

export class EdiAttrSetsComponent extends AdminPageComponent implements OnInit {
    idlClass = 'aeas';
    classLabel: string;

    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('ediAttrSetProvidersDialog', { static: false }) ediAttrSetProvidersDialog: EdiAttrSetProvidersDialogComponent;
    @ViewChild('ediAttrSetEditDialog', { static: false }) ediAttrSetEditDialog: EdiAttrSetEditDialogComponent;
    @ViewChild('alertDialog', {static: false}) private alertDialog: AlertDialogComponent;
    @ViewChild('confirmDel', { static: true }) confirmDel: ConfirmDialogComponent;

    cellTextGenerator: GridCellTextGenerator;
    notOneSelectedRow: (rows: IdlObject[]) => boolean;

    dataSource = new GridDataSource();

    ngOnInit() {
        this.notOneSelectedRow = (rows: IdlObject[]) => (rows.length !== 1);
        this.cellTextGenerator = {
            view_providers: row => '',
            num_providers: row => '',
        };
        this.fieldOrder = 'label';
        this.defaultNewRecord = this.idl.create('aeas');

        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idlClass] = sort[0].name + ' ' + sort[0].dir;
            } else if (this.sortField) {
                // Default sort field
                orderBy[this.idlClass] = this.sortField;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy,
                flesh: 1,
                flesh_fields: {
                    aeas: ['edi_accounts']
                }
            };
            const reqOps = { };

            if (!this.contextOrg && !Object.keys(this.dataSource.filters).length) {
                // No org filter -- fetch all rows
                return this.pcrud.retrieveAll(
                    this.idlClass, searchOps, reqOps)
                    .pipe(mergeMap((row) => this.countProviders(row)));
            }

            const search: any = new Array();
            const orgFilter: any = {};

            if (this.orgField && (this.searchOrgs || this.contextOrg)) {
                orgFilter[this.orgField] =
                    this.searchOrgs.orgIds || [this.contextOrg.id()];
                search.push(orgFilter);
            }

            Object.keys(this.dataSource.filters).forEach(key => {
                Object.keys(this.dataSource.filters[key]).forEach(key2 => {
                    search.push(this.dataSource.filters[key][key2]);
                });
            });

            return this.pcrud.search(this.idlClass, search, searchOps, reqOps)
                .pipe(mergeMap((row) => this.countProviders(row)));
        };

        super.ngOnInit();

        this.classLabel = this.idlClassDef.label;
        this.includeOrgDescendants = true;
    }

    countProviders(row: IdlObject): Observable<IdlObject> {
        row['num_providers'] = (new Set( row.edi_accounts().map(r => r.provider()) )).size;
        return of(row);
    }

    openEdiAttrSetProvidersDialog(id: number) {
        this.ediAttrSetProvidersDialog.attrSetId = id;
        this.ediAttrSetProvidersDialog.open({size: 'lg'});
    }

    deleteIfPossible(rows: IdlObject[]) {
        if (rows.length > 0) {
            if (rows[0].num_providers > 0) {
                this.alertDialog.open();
            } else {
                this.confirmDel.open().subscribe(confirmed => {
                    if (!confirmed) { return; }
                    super.doDelete([ rows[0] ]);
                });
            }
        }
    }

    showEditAttrSetDialog(successString: StringComponent, failString: StringComponent): Promise<any> {
        return new Promise((resolve, reject) => {
            this.ediAttrSetEditDialog.open({size: 'lg', scrollable: true}).subscribe(
                { next: result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                    resolve(result);
                }, error: (error: unknown) => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                } }
            );
        });
    }

    createNew() {
        this.ediAttrSetEditDialog.mode = 'create';
        this.showEditAttrSetDialog(this.createString, this.createErrString);
    }

    editSelected(rows: IdlObject[]) {
        if (rows.length <= 0) { return; }
        this.ediAttrSetEditDialog.mode = 'update';
        this.ediAttrSetEditDialog.attrSetId = rows[0].id();
        this.showEditAttrSetDialog(this.successString, this.updateFailedString);
    }

    cloneSelected(rows: IdlObject[]) {
        if (rows.length <= 0) { return; }
        this.ediAttrSetEditDialog.mode = 'clone';
        this.ediAttrSetEditDialog.cloneSource = rows[0].id();
        this.showEditAttrSetDialog(this.createString, this.createErrString);
    }
}
