import {Component, ViewChild, Input, OnInit, AfterViewInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {tap} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PermService} from '@eg/core/perm.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';

@Component({
  templateUrl: 'perms.component.html',
  selector: 'eg-patron-perms'
})
export class PatronPermsComponent implements OnInit {

    @Input() patronId: number;
    workOuMaps: IdlObject[];
    workOuSelector: {[orgId: number]: boolean} = {};
    workableOrgs: IdlObject[] = [];
    canAssignWorkOrgs: {[orgId: number]: boolean} = {};
    myPermMaps: IdlObject[] = [];
    userPermMaps: IdlObject[] = [];
    allPerms: IdlObject[] = [];
    loading = true;

    permsApplied: {[id: number]: boolean} = {};
    permDepths: {[id: number]: number} = {};
    permGrantable: {[id: number]: boolean} = {};
    orgDepths: number[];

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService,
        private perms: PermService
    ) {
    }

    ngOnInit() {

        this.workableOrgs = this.org.filterList({canHaveUsers: true})
        .sort((o1, o2) => o1.shortname() < o2.shortname() ? -1 : 1);

        const depths = {};
        this.org.list().forEach(org => depths[org.ou_type().depth()] = true);
        this.orgDepths = Object.keys(depths).map(d => Number(d)).sort();

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.get_work_ous',
            this.auth.token(), this.patronId).toPromise()

        .then(maps => {
            this.workOuMaps = maps;
            maps.forEach(map => this.workOuSelector[map.work_ou()] = true);
        })

        .then(_ => { // All permissions
            return this.pcrud.retrieveAll('ppl', {order_by: {ppl: 'code'}})
            .pipe(tap(perm => this.allPerms.push(perm))).toPromise();
        })

        .then(_ => { // Target user permissions
            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.permissions.user_perms.retrieve',
                this.auth.token(), this.patronId).toPromise()
            .then(maps => {
                this.userPermMaps = maps;
                maps.forEach(m => {
                    this.permsApplied[m.perm()] = true;
                    this.permDepths[m.perm()] = m.depth();
                    this.permGrantable[m.perm()] = m.grantable() === 't';

                });
            });
        })

        .then(_ => { // My permissions
            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.permissions.user_perms.retrieve',
                this.auth.token()).toPromise()
            .then(perms => this.myPermMaps = perms);
        })

        .then(_ => this.perms.hasWorkPermAt(['ASSIGN_WORK_ORG_UNIT'], true))
        .then(perms => {
            const orgIds = perms.ASSIGN_WORK_ORG_UNIT;
            orgIds.forEach(id => this.canAssignWorkOrgs[id] = true);
        })
        .then(_ => this.loading = false);
    }

    save() {
        // open-ils.actor.user.work_ous.update
    }
}

