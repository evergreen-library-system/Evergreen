import {Injectable} from '@angular/core';
import {NetService} from './net.service';
import {OrgService} from './org.service';
import {AuthService} from './auth.service';

interface HasPermAtResult {
    [permName: string]: any[]; // org IDs or org unit objects
}

interface HasPermHereResult {
    [permName: string]: boolean;
}

@Injectable({providedIn: 'root'})
export class PermService {

    constructor(
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
    ) {}

    // workstation not required.
    hasWorkPermAt(permNames: string[], asId?: boolean): Promise<HasPermAtResult> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.has_work_perm_at.batch',
            this.auth.token(), permNames
        ).toPromise().then(resp => {
            const answer: HasPermAtResult = {};
            permNames.forEach(perm => {
                let orgs = [];
                resp[perm].forEach(oneOrg => {
                    orgs = orgs.concat(this.org.descendants(oneOrg, asId));
                });
                answer[perm] = orgs;
            });

            return answer;
        });
    }

    // workstation required
    hasWorkPermHere(permNames: string | string[]): Promise<HasPermHereResult> {
        permNames = [].concat(permNames);
        const wsId: number = +this.auth.user().wsid();

        if (!wsId) {
            return Promise.reject('hasWorkPermHere requires a workstation');
        }

        const ws_ou: number = +this.auth.user().ws_ou();
        return this.hasWorkPermAt(permNames, true).then(resp => {
            const answer: HasPermHereResult = {};
            Object.keys(resp).forEach(perm => {
                answer[perm] = resp[perm].indexOf(ws_ou) > -1;
            });
            return answer;
        });
    }
}
