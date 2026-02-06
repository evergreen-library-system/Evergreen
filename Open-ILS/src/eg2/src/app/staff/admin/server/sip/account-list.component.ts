import {Component, ViewChild, OnInit} from '@angular/core';
import {Router} from '@angular/router';
import {Observable} from 'rxjs';
import {PcrudService} from '@eg/core/pcrud.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import { StaffBannerComponent } from '@eg/staff/share/staff-banner.component';
import { GridModule } from '@eg/share/grid/grid.module';

@Component({
    templateUrl: './account-list.component.html',
    imports: [
        ConfirmDialogComponent,
        GridModule,
        StaffBannerComponent
    ]
})
export class SipAccountListComponent implements OnInit {

    gridSource: GridDataSource = new GridDataSource();
    @ViewChild('grid') grid: GridComponent;
    @ViewChild('confirmDelete') confirmDelete: ConfirmDialogComponent;

    constructor(
        private router: Router,
        private pcrud: PcrudService
    ) {}

    ngOnInit() {
        this.gridSource.getRows = (pager: Pager, sort: any[]) => {
            return this.fetchAccounts(pager, sort);
        };
    }

    fetchAccounts(pager: Pager, sort: any[]): Observable<any> {

        const orderBy: any = {sipacc: 'sip_username'};
        if (sort.length) {
            orderBy.sipacc = sort[0].name + ' ' + sort[0].dir;
        }

        const query = [{id: {'!=': null}}];

        Object.keys(this.gridSource.filters).forEach(key => {
            Object.keys(this.gridSource.filters[key]).forEach(key2 => {
                query.push(this.gridSource.filters[key][key2]);
            });
        });

        return this.pcrud.search('sipacc', query, {
            offset: pager.offset,
            limit: pager.limit,
            order_by: orderBy,
            flesh: 1,
            flesh_fields: {sipacc: ['usr', 'setting_group', 'workstation']}
        });
    }

    openAccount(row: any) {
        this.router.navigate([`/staff/admin/server/sip/account/${row.id()}`]);
    }

    newAccount() {
        this.router.navigate(['/staff/admin/server/sip/account/new']);
    }

    deleteSelected(rows: any[]) {
        if (rows.length === 0) { return; }

        this.confirmDelete.open().subscribe(confirmed => {
            if (confirmed) {
                rows.forEach(row => row.isdeleted(true));
                this.pcrud.autoApply(rows).toPromise().then(_ => {
                    this.gridSource.reset();
                    this.grid.reload();
                });
            }
        });
    }
}

