import {Component, ViewChild, OnInit} from '@angular/core';
import {EMPTY, map} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringService} from '@eg/share/string/string.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';

@Component({
    templateUrl: './list.component.html'
})
export class NegativeBalancesComponent implements OnInit {

    dataSource: GridDataSource = new GridDataSource();
    contextOrg: IdlObject;
    contextOrgLoaded = false;
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('grid') private grid: GridComponent;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService,
        private strings: StringService,
        private toast: ToastService
    ) {}

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
