import {Injectable} from '@angular/core';
import {Observable} from 'rxjs';
import {tap} from 'rxjs/operators';
import {IdlObject, IdlService} from './idl.service';
import {NetService} from './net.service';
import {AuthService} from './auth.service';
import {PcrudService} from './pcrud.service';
import {DbStoreService} from './db-store.service';

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

    private orgTypeMap: {[id: number]: IdlObject} = {};
    private orgTypeList: IdlObject[] = [];

    constructor(
        private db: DbStoreService,
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

    typeList(): IdlObject[] {
        return this.orgTypeList;
    }

    typeMap(): {[id: number]: IdlObject} {
        return this.orgTypeMap;
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
            node.children().sort((a, b) => {
                return a[sortField]() < b[sortField]() ? -1 : 1;
            })
        );
        node.children().forEach(n => this.sortTree(sortField, n));
    }

    absorbTree(node?: IdlObject): void {
        if (!node) {
            node = this.orgTree;
            this.orgMap = {};
            this.orgList = [];
            this.orgTypeMap = {};
        }
        this.orgMap[node.id()] = node;
        this.orgList.push(node);

        this.orgTypeMap[node.ou_type().id()] = node.ou_type();
        if (!this.orgTypeList.filter(t => t.id() === node.ou_type().id())[0]) {
            this.orgTypeList.push(node.ou_type());
        }

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

    private appendSettingsFromCache(names: string[], batch: OrgSettingsBatch) {
        names.forEach(name => {
            if (name in this.settingsCache) {
                batch[name] = this.settingsCache[name];
            }
        });
    }

    // Pulls setting values from IndexedDB.
    // Update local cache with any values found.
    private appendSettingsFromDb(names: string[],
        batch: OrgSettingsBatch): Promise<OrgSettingsBatch> {

        if (names.length === 0) { return Promise.resolve(batch); }

        return this.db.request({
            schema: 'cache',
            table: 'Setting',
            action: 'selectWhereIn',
            field: 'name',
            value: names
        }).then(settings => {

            // array of key => JSON-string objects
            settings.forEach(setting => {
                const value = JSON.parse(setting.value);
                // propagate to local cache as well
                batch[setting.name] = this.settingsCache[setting.name] = value;
            });

            return batch;
        }).catch(_ => batch);
    }

    // Add values for the list of named settings from the 'batch' to
    // IndexedDB, copying the local cache as well.
    private addSettingsToDb(names: string[],
        batch: OrgSettingsBatch): Promise<OrgSettingsBatch> {

        const rows = [];
        names.forEach(name => {
            // Anything added to the db should also be cached locally.
            this.settingsCache[name] = batch[name];
            rows.push({name: name, value: JSON.stringify(batch[name])});
        });

        if (rows.length === 0) { return Promise.resolve(batch); }

        return this.db.request({
            schema: 'cache',
            table: 'Setting',
            action: 'insertOrReplace',
            rows: rows
        }).then(_ => batch).catch(_ => batch);
    }

    /**
     * Append the named settings from the network to the in-progress
     * batch of settings.  'auth' is null for anonymous lookup.
     */
    private appendSettingsFromNet(orgId: number, names: string[],
        batch: OrgSettingsBatch, auth?: string): Promise<OrgSettingsBatch> {

        if (names.length === 0) { return Promise.resolve(batch); }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.ou_setting.ancestor_default.batch',
            orgId, names, auth

        ).pipe(tap(settings => {
            Object.keys(settings).forEach(key => {
                const val = settings[key]; // null or hash
                batch[key] = val ? val.value : null;
            });
        })).toPromise().then(_ => batch);
    }

    // Given a set of setting names and an in-progress settings batch,
    // return the list of names which are not yet represented in the ,
    // indicating their data needs to be fetched from the next layer up
    // (cache, network, etc.).
    settingNamesRemaining(names: string[], settings: OrgSettingsBatch): string[] {
        return names.filter(name => !(name in settings));
    }

    // Returns a key/value batch of org unit settings.
    // Cacheable settings (orgId === here) are pulled from local cache,
    // then IndexedDB, then the network.  Non-cacheable settings are
    // fetched from the network each time.
    settings(name: string | string[],
        orgId?: number, anonymous?: boolean): Promise<OrgSettingsBatch> {

        let names = [].concat(name);
        let auth: string = null;
        let useCache = false;
        const batch: OrgSettingsBatch = {};

        if (names.length === 0) { return Promise.resolve(batch); }

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

        if (!useCache) {
            return this.appendSettingsFromNet(orgId, names, batch, auth);
        }

        this.appendSettingsFromCache(names, batch);
        names = this.settingNamesRemaining(names, batch);

        return this.appendSettingsFromDb(names, batch)
        .then(_ => {

            names = this.settingNamesRemaining(names, batch);

            return this.appendSettingsFromNet(orgId, names, batch, auth)
            .then(__ => this.addSettingsToDb(names, batch));
        });
    }

    // remove setting values cached in the indexeddb settings table.
    clearCachedSettings(): Promise<any> {
        return this.db.request({
            schema: 'cache',
            table: 'Setting',
            action: 'deleteAll'
        }).catch(_ => null);
    }
}
