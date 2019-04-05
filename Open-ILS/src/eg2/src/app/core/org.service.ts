import {Injectable} from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject, IdlService} from './idl.service';
import {NetService} from './net.service';
import {AuthService} from './auth.service';
import {PcrudService} from './pcrud.service';

type OrgNodeOrId = number | IdlObject;

interface OrgFilter {
    canHaveUsers?: boolean;
    canHaveVolumes?: boolean;
    opacVisible?: boolean;
    inList?: number[];
    notInList?: number[];
}

interface OrgSettingsBatch {
    [key: string]: any;
}

@Injectable({providedIn: 'root'})
export class OrgService {

    private orgList: IdlObject[] = [];
    private orgTree: IdlObject; // root node + children
    private orgMap: {[id: number]: IdlObject} = {};
    private settingsCache: OrgSettingsBatch = {};

    constructor(
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService
    ) {}

    get(nodeOrId: OrgNodeOrId): IdlObject {
        if (typeof nodeOrId === 'object') {
            return nodeOrId;
        }
        return this.orgMap[nodeOrId];
    }

    list(): IdlObject[] {
        return this.orgList;
    }

    // Returns a list of org unit type objects
    typeList(): IdlObject[] {
        const types = [];
        this.list().forEach(org => {
            if ((types.filter(t => t.id() === org.ou_type().id())).length === 0) {
                types.push(org.ou_type());
            }
        });
        return types;
    }

    /**
     * Returns a list of org units that match the selected criteria.
     * All filters must match for an org to be included in the result set.
     * Unset filter options are ignored.
     */
    filterList(filter: OrgFilter, asId?: boolean): any[] {
        const list = [];
        this.list().forEach(org => {

            const chu = filter.canHaveUsers;
            if (chu && !this.canHaveUsers(org)) { return; }
            if (chu === false && this.canHaveUsers(org)) { return; }

            const chv = filter.canHaveVolumes;
            if (chv && !this.canHaveVolumes(org)) { return; }
            if (chv === false && this.canHaveVolumes(org)) { return; }

            const ov = filter.opacVisible;
            if (ov && !this.opacVisible(org)) { return; }
            if (ov === false && this.opacVisible(org)) { return; }

            if (filter.inList && !filter.inList.includes(org.id())) {
                return;
            }

            if (filter.notInList && filter.notInList.includes(org.id())) {
                return;
            }

            // All filter tests passed.  Add it to the list
            list.push(asId ? org.id() : org);
        });

        return list;
    }

    tree(): IdlObject {
        return this.orgTree;
    }

    // get the root OU
    root(): IdlObject {
        return this.orgList[0];
    }

    // list of org_unit objects or IDs for ancestors + me
    ancestors(nodeOrId: OrgNodeOrId, asId?: boolean): any[] {
        let node = this.get(nodeOrId);
        if (!node) { return []; }
        const nodes = [node];
        while ( (node = this.get(node.parent_ou())) ) {
            nodes.push(node);
        }
        if (asId) {
            return nodes.map(n => n.id());
        }
        return nodes;
    }

    // tests that a node can have users
    canHaveUsers(nodeOrId): boolean {
        return this.get(nodeOrId).ou_type().can_have_users() === 't';
    }

    // tests that a node can have volumes
    canHaveVolumes(nodeOrId): boolean {
        return this
            .get(nodeOrId)
            .ou_type()
            .can_have_vols() === 't';
    }

    opacVisible(nodeOrId): boolean {
        return this.get(nodeOrId).opac_visible() === 't';
    }

    // list of org_unit objects  or IDs for me + descendants
    descendants(nodeOrId: OrgNodeOrId, asId?: boolean): any[] {
        const node = this.get(nodeOrId);
        if (!node) { return []; }
        const nodes = [];
        const descend = (n) => {
            nodes.push(n);
            n.children().forEach(descend);
        };
        descend(node);
        if (asId) {
            return nodes.map(n => n.id());
        }
        return nodes;
    }

    // list of org_unit objects or IDs for ancestors + me + descendants
    fullPath(nodeOrId: OrgNodeOrId, asId?: boolean): any[] {
        const list = this.ancestors(nodeOrId, false).concat(
          this.descendants(nodeOrId, false).slice(1));
        if (asId) {
            return list.map(n => n.id());
        }
        return list;
    }

    sortTree(sortField?: string, node?: IdlObject): void {
        if (!sortField) { sortField = 'shortname'; }
        if (!node) { node = this.orgTree; }
        node.children(
            node.children.sort((a, b) => {
                return a[sortField]() < b[sortField]() ? -1 : 1;
            })
        );
        node.children.forEach(n => this.sortTree(n));
    }

    absorbTree(node?: IdlObject): void {
        if (!node) {
            node = this.orgTree;
            this.orgMap = {};
            this.orgList = [];
        }
        this.orgMap[node.id()] = node;
        this.orgList.push(node);
        node.children().forEach(c => this.absorbTree(c));
    }

    /**
     * Grabs all of the org units from the server, chops them up into
     * various shapes, then returns an "all done" promise.
     */
    fetchOrgs(): Promise<void> {
        return this.pcrud.search('aou', {parent_ou : null},
            {flesh : -1, flesh_fields : {aou : ['children', 'ou_type']}},
            {anonymous : true}
        ).toPromise().then(tree => {
            // ingest tree, etc.
            this.orgTree = tree;
            this.absorbTree();
        });
    }

    /**
     * Populate 'target' with settings from cache where available.
     * Return the list of settings /not/ pulled from cache.
     */
    private settingsFromCache(names: string[], target: any) {
        const cacheKeys = Object.keys(this.settingsCache);

        cacheKeys.forEach(key => {
            const matchIdx = names.indexOf(key);
            if (matchIdx > -1) {
                target[key] = this.settingsCache[key];
                names.splice(matchIdx, 1);
            }
        });

        return names;
    }

    /**
     * Fetch org settings from the network.
     * 'auth' is null for anonymous lookup.
     */
    private settingsFromNet(orgId: number,
        names: string[], auth?: string): Promise<any> {

        const settings = {};
        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.ou_setting.ancestor_default.batch',
                orgId, names, auth
            ).subscribe(
                blob => {
                    Object.keys(blob).forEach(key => {
                        const val = blob[key]; // null or hash
                        settings[key] = val ? val.value : null;
                    });
                    resolve(settings);
                },
                err => reject(err)
            );
        });
    }


    /**
     *
     */
    settings(name: string | string[],
        orgId?: number, anonymous?: boolean): Promise<OrgSettingsBatch> {

        let names = [].concat(name);
        const settings = {};
        let auth: string = null;
        let useCache = false;

        if (this.auth.user()) {
            if (orgId) {
                useCache = Number(orgId) === Number(this.auth.user().ws_ou());
            } else {
                orgId = this.auth.user().ws_ou();
                useCache = true;
            }

            // avoid passing auth token when anonymous is requested.
            if (!anonymous) {
                auth = this.auth.token();
            }

        } else if (!anonymous) {
            console.warn('Attempt to fetch org setting(s)',
                name, 'in non-anonymous mode without an authtoken');
            return Promise.resolve({});
        }

        if (useCache) {
            names = this.settingsFromCache(names, settings);
        }

        // All requested settings found in cache (or name list is empty)
        if (names.length === 0) {
            return Promise.resolve(settings);
        }

        return this.settingsFromNet(orgId, names, auth)
        .then(sets => {
            if (useCache) {
                Object.keys(sets).forEach(key => {
                    this.settingsCache[key] = sets[key];
                });
            }
            return sets;
        });
    }
}
