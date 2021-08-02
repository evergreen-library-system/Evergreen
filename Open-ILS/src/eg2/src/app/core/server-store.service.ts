/**
 * Set and get server-stored settings.
 */
import {Injectable} from '@angular/core';
import {tap} from 'rxjs/operators';
import {AuthService} from './auth.service';
import {NetService} from './net.service';
import {DbStoreService} from './db-store.service';

// Settings summary objects returned by the API
interface ServerSettingSummary {
    name: string;
    value: string;
    has_org_setting: boolean;
    has_user_setting: boolean;
    has_workstation_setting: boolean;
}

@Injectable({providedIn: 'root'})
export class ServerStoreService {

    cache: {[key: string]: any};

    constructor(
        private db: DbStoreService,
        private net: NetService,
        private auth: AuthService) {
        this.cache = {};
    }

    setItem(key: string, value: any): Promise<any> {

        if (!this.auth.token()) {
            return Promise.reject('Auth required to apply settings');
        }

        const setting: any = {};
        setting[key] = value;

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.settings.apply.user_or_ws',
            this.auth.token(), setting)

        .toPromise().then(appliedCount => {

            if (Number(appliedCount) <= 0) { // no value applied
                return Promise.reject(
                    `No user or workstation setting type exists for: "${key}".\n` +
                    'Create a ws/user setting type or use setLocalItem() to ' +
                    'store the value locally.'
                );
            }

            return this.addSettingsToDb(setting);
        });
    }

    // Returns a single setting value
    getItem(key: string): Promise<any> {
        return this.getItemBatch([key]).then(
            settings => settings[key]
        );
    }

    // Sync call for items known to be cached locally.
    getItemCached(key: string): any {
        return this.cache[key];
    }

    // Sync batch call for items known to be cached locally
    getItemBatchCached(keys: string[]): {[key: string]: any} {
        const values: any = {};
        keys.forEach(key => {
            if (key in this.cache) {
                values[key] = this.cache[key];
            }
        });
        return values;
    }

    // Returns a set of key/value pairs for the requested settings
    getItemBatch(keys: string[]): Promise<{[key: string]: any}> {

        let values: any = {};
        keys.forEach(key => {
            if (key in this.cache) {
                values[key] = this.cache[key];
            }
        });

        if (keys.length === Object.keys(values).length) {
            // All values are cached already
            return Promise.resolve(values);
        }

        if (!this.auth.token()) {
            // Authtokens require for fetching server settings, but
            // calls to retrieve settings could potentially occur
            // before auth completes -- Ideally not, but just to be safe.
            return Promise.resolve({});
        }

        // IndexedDB call required.
        const dbKeys = [];

        keys.forEach(key => {
            if (!Object.keys(values).includes(key)) {
                dbKeys.push(key);
            }
        });

        return this.getSettingsFromDb(dbKeys) // Also appends to local cache.
        .then(dbValues => values = Object.assign(values, dbValues))
        .then(_ => {

            const serverKeys = [];
            keys.forEach(key => {
                if (!Object.keys(values).includes(key)) {
                    serverKeys.push(key);
                }
            });

            if (serverKeys.length === 0) { return values; }

            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.settings.retrieve',
                serverKeys, this.auth.token()

            ).pipe(tap((summary: ServerSettingSummary) => {
                this.cache[summary.name] =
                    values[summary.name] = summary.value;

            })).toPromise().then(__ => {

                const dbSets: any = {};
                serverKeys.forEach(sKey => dbSets[sKey] = values[sKey]);

                return this.addSettingsToDb(dbSets);

            });
        });
    }

    removeItem(key: string): Promise<any> {
        return this.setItem(key, null);
    }

    private addSettingsToDb(values: {[key: string]: any}): Promise<{[key: string]: any}> {

        const rows = [];
        Object.keys(values).forEach(name => {
            // Anything added to the db should also be cached locally.
            this.cache[name] = values[name];
            rows.push({name: name, value: JSON.stringify(values[name])});
        });

        if (rows.length === 0) { return Promise.resolve(values); }

        return this.db.request({
            schema: 'cache',
            table: 'Setting',
            action: 'insertOrReplace',
            rows: rows
        }).then(_ => values).catch(_ => values);
    }

    getSettingsFromDb(names: string[]): Promise<{[key: string]: any}> {
        if (names.length === 0) { return Promise.resolve({}); }

        const values: any = {};

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
                values[setting.name] = this.cache[setting.name] = value;
            });

            return values;
        }).catch(_ => values);
    }
}

