import {Pager} from '@eg/share/util/pager';
import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute} from '@angular/router';
import {FormatService} from '@eg/core/format.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {AdminPageComponent} from '../../../share/admin-page/admin-page.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    templateUrl: './floating-group.component.html'
})

export class FloatingGroupComponent extends AdminPageComponent implements OnInit {

    idlClass = 'cfg';

    gridDataSource: GridDataSource = new GridDataSource();

    @ViewChild('grid', {static: true}) grid: GridComponent;
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
        private router: Router
    ) {
        super(route, ngLocation, format, idl, org, auth, pcrud, perm, toast);
    }

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

        this.grid.onRowActivate.subscribe(
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
        this.delConfirm.open().subscribe(confirmed => {
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
