import {Component, ViewChild, Input, OnInit, AfterViewInit} from '@angular/core';
import {Observable, concatMap, tap, finalize} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PermService} from '@eg/core/perm.service';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';

@Component({
    templateUrl: 'perms.component.html',
    selector: 'eg-patron-perms'
})
export class PatronPermsComponent implements OnInit, AfterViewInit {

    @Input() patronId: number;

    myPermMaps:  {[permId: number]: IdlObject} = {};
    userPermMaps: {[permId: number]: IdlObject} = {};
    userWorkOuMaps: {[orgId: number]: IdlObject} = {};

    workableOrgs: IdlObject[] = [];
    canAssignWorkOrgs: {[orgId: number]: boolean} = {};
    allPerms: IdlObject[] = [];
    loading = true;

    orgDepths: number[];

    @ViewChild('progress') private progress: ProgressInlineComponent;

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
    }

    ngAfterViewInit() {

        return this.reload().toPromise()

            .then(_ => { // All permissions
                this.progress.increment();
                return this.pcrud.retrieveAll('ppl', {order_by: {ppl: 'code'}})
                    .pipe(tap(perm => this.allPerms.push(perm))).toPromise();
            })

            .then(_ => { // My permissions
                this.progress.increment();
                return this.net.request(
                    'open-ils.actor',
                    'open-ils.actor.permissions.user_perms.retrieve',
                    this.auth.token()).toPromise()
                    .then(maps => {
                        this.progress.increment();
                        maps.forEach(m => this.myPermMaps[m.perm()] = m);
                    });
            })

            .then(_ => {
                this.progress.increment();
                return this.perms.hasWorkPermAt(['ASSIGN_WORK_ORG_UNIT'], true);
            })

            .then(perms => {
                this.progress.increment();
                const orgIds = perms.ASSIGN_WORK_ORG_UNIT;
                orgIds.forEach(id => this.canAssignWorkOrgs[id] = true);
            })

            .then(_ => this.loading = false);
    }

    reload(): Observable<any> {

        this.userWorkOuMaps = {};
        this.userPermMaps = {};
        this.progress.increment();

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.get_work_ous',
            this.auth.token(), this.patronId

        ).pipe(tap(maps => {
            this.progress.increment();
            maps.forEach(map => this.userWorkOuMaps[map.work_ou()] = map);

        })).pipe(concatMap(_ => { // User perm maps
            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.permissions.user_perms.retrieve',
                this.auth.token(), this.patronId
            );

        })).pipe(tap(maps => {
            this.progress.increment();
            maps.forEach(m => this.userPermMaps[m.perm()] = m);
        }));
    }

    userHasWorkOu(orgId: number): boolean {
        return (
            this.userWorkOuMaps[orgId] &&
            !this.userWorkOuMaps[orgId].isdeleted()
        );
    }

    userWorkOuChange(orgId: number, applied: boolean) {
        const map = this.userWorkOuMaps[orgId];

        if (map) {
            map.isdeleted(!applied);
        } else {
            const newMap = this.idl.create('puwoum');
            newMap.isnew(true);
            newMap.usr(this.patronId);
            newMap.work_ou(orgId);
            this.userWorkOuMaps[orgId] = newMap;
        }
    }

    canGrantPerm(perm: IdlObject): boolean {
        if (this.auth.user().super_user() === 't') { return true; }
        const map = this.myPermMaps[perm.id()];
        return map && Number(map.grantable()) === 1;
    }

    canGrantPermAtDepth(perm: IdlObject): number {
        if (this.auth.user().super_user() === 't') {
            return this.org.root().ou_type().depth();
        } else {
            const map = this.myPermMaps[perm.id()];
            return map ? map.depth() : NaN;
        }
    }

    userHasPerm(perm: IdlObject): boolean {
        return (
            this.userPermMaps[perm.id()] &&
            !this.userPermMaps[perm.id()].isdeleted()
        );
    }

    findOrCreatePermMap(perm: IdlObject): IdlObject {
        if (this.userPermMaps[perm.id()]) {
            return this.userPermMaps[perm.id()];
        }

        const map = this.idl.create('pupm');
        map.isnew(true);
        map.usr(this.patronId);
        map.perm(perm.id());
        return this.userPermMaps[perm.id()] = map;
    }

    permApplyChanged(perm: IdlObject, applied: boolean) {
        const map = this.findOrCreatePermMap(perm);
        map.isdeleted(!applied);
        map.ischanged(true);
    }

    userHasPermAtDepth(perm: IdlObject): number {
        if (this.userPermMaps[perm.id()]) {
            return this.userPermMaps[perm.id()].depth();
        } else {
            return null;
        }
    }

    permDepthChanged(perm: IdlObject, depth: number) {
        const map = this.findOrCreatePermMap(perm);
        map.depth(depth);
        map.ischanged(true);
    }

    userPermIsGrantable(perm: IdlObject): boolean {
        return (
            this.userPermMaps[perm.id()] &&
            Number(this.userPermMaps[perm.id()].grantable()) === 1
        );
    }

    grantableChanged(perm: IdlObject, grantable: boolean) {
        const map = this.findOrCreatePermMap(perm);
        map.grantable(grantable ? 1 : 0); // API uses 1/0 not t/f
        map.ischanged(true);
    }

    save() {
        this.loading = true;

        // Scrub the unmodified values to avoid sending a huge pile
        // of perms especially.

        const ouMaps = Object.values(this.userWorkOuMaps)
            .filter(map => map.isnew() || map.ischanged() || map.isdeleted());

        const permMaps = Object.values(this.userPermMaps)
            .filter(map => map.isnew() || map.ischanged() || map.isdeleted());

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.work_ous.update',
            this.auth.token(), ouMaps

        ).pipe(concatMap(_ => {

            this.progress.reset();
            this.progress.increment();

            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.permissions.update',
                this.auth.token(), permMaps
            );
        }))
            .pipe(concatMap(_ => this.reload()))
            .pipe(finalize(() => this.loading = false)).subscribe();
    }

    cannotSave(): boolean {
        return Object.values(this.userPermMaps)
            .filter(map => map.depth() === null || map.depth() === undefined)
            .length > 0;
    }
}

