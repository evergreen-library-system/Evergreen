import { Component, ViewChild, OnInit, inject } from '@angular/core';
import {EMPTY, map} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: './list.component.html',
    imports: [StaffCommonModule]
})
export class NegativeBalancesComponent implements OnInit {
    private org = inject(OrgService);
    private auth = inject(AuthService);
    private net = inject(NetService);


    dataSource: GridDataSource = new GridDataSource();
    contextOrg: IdlObject;
    contextOrgLoaded = false;
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('grid') private grid: GridComponent;

    ngOnInit() {
        this.contextOrg = this.org.get(this.auth.user().ws_ou());

        this.cellTextGenerator = {
            barcode: row => row.card().barcode()
        };

        this.dataSource.getRows = (pager: Pager, sort: any[]) => {

            if (!this.contextOrgLoaded) {
                // Still determining the default context org unit.
                return EMPTY;
            }

            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.users.negative_balance',
                this.auth.token(), this.contextOrg.id(),
                {limit: pager.limit, offset: pager.offset, org_descendants: true}
            ).pipe(map(data => {

                const user = data.usr;
                user._extras = {
                    balance_owed: data.balance_owed,
                    last_billing_activity: data.last_billing_activity,
                };

                return user;
            }));
        };
    }

    orgChanged(org: IdlObject) {
        if (org) {
            this.contextOrg = org;
            this.grid.reload();
        }
    }
}
