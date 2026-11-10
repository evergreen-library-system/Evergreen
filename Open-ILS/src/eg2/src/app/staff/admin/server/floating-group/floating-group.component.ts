import {Pager} from '@eg/share/util/pager';
import { Component, OnInit, inject, viewChild } from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {AdminPageComponent} from '../../../share/admin-page/admin-page.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';

@Component({
    templateUrl: './floating-group.component.html',
    imports: [
        FmRecordEditorComponent,
        StaffCommonModule
    ]
})

export class FloatingGroupComponent extends AdminPageComponent implements OnInit {
    private router = inject(Router);


    idlClass = 'cfg';

    gridDataSource: GridDataSource = new GridDataSource();

    protected delConfirm = viewChild.required<ConfirmDialogComponent>('delConfirm');

    ngOnInit() {
        super.ngOnInit();
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {

            const orderBy: any = {};
            if (sort.length) {
                orderBy.cfg = sort[0].name + ' ' + sort[0].dir;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            return this.pcrud.retrieveAll('cfg', searchOps);
        };

        this.grid().onRowActivate.subscribe(
            (idlThing: IdlObject) => {
                const idToEdit = idlThing.id();
                this.navigateToEditPage(idToEdit);
            }
        );
    }

    editSelected = (floatingGroups: IdlObject[]) => {
        const idToEdit = floatingGroups[0].id();
        this.navigateToEditPage(idToEdit);
    };

    deleteSelected = (idlThings: IdlObject[]) => {
        this.delConfirm().open().subscribe(confirmed => {
            if (!confirmed) { return; }
            super.doDelete(idlThings);
        });
    };

    navigateToEditPage(id: any) {
        this.router.navigate(['/staff/admin/server/config/floating_group/' + id]);
    }

    // this was left mostly blank to ensure a modal does not open for edits
    showEditDialog(idlThing: IdlObject): Promise<any> {
        return;
    }

}
