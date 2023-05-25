import {Component, OnInit, ViewChild} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';

@Component({
    templateUrl: 'list.component.html'
})
export class ClaimEligibleListComponent implements OnInit {

    lids: IdlObject[];
    contextOrg: number;

    @ViewChild(LineitemListComponent, { static: false }) lineitemList: LineitemListComponent;

    constructor(
        private net: NetService,
        private auth: AuthService,
    ) {}

    ngOnInit() {
        console.debug('ClaimEligibleListComponent',this);
        this.contextOrg = this.initialContextOrg();
        this.fetchEligibleLids();
    }

    changeContextOrg(event: IdlObject) {
        if (event.id() !== this.contextOrg) {
            this.contextOrg = event.id();
            console.debug('contextOrg',this.contextOrg);
            this.fetchEligibleLids();
        }
    }

    initialContextOrg() {
        return this.auth.user().ws_ou();
    }

    fetchEligibleLids() {
        this.net.request('open-ils.acq', 'open-ils.acq.claim.eligible.lineitem_detail.atomic',
            this.auth.token(), {ordering_agency: this.contextOrg}
        ).subscribe({
            next: lids => {
                console.debug('eligible lids', lids);
                this.lids = lids;
                if (!this.lids.length) {
                    // TODO: need to empty the list
                }
            },
            error: (err: unknown) => {
                console.warn('error retrieving eligible lids', err);
            }
        });
    }

}
