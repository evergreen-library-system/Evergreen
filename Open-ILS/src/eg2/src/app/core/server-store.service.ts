/**
 * Set and get server-stored settings.
 */
import {Injectable} from '@angular/core';
import {AuthService} from './auth.service';
import {NetService} from './net.service';

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

    cache: {[key: string]: ServerSettingSummary};

    constructor(
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

            if (Number(appliedCount) > 0) { // value applied
                return this.cache[key] = value;
            }

            return Promise.reject(
                `No user or workstation setting type exists for: "${key}".\n` +
                'Create a ws/user setting type or use setLocalItem() to ' +
                'store the value locally.'
            );
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
    getItemBatch(keys: string[]): Promise<any> {

        const values: any = {};
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

        // Server call required.  Limit the settings to lookup to those
        // we don't already have cached.
        const serverKeys = [];
        keys.forEach(key => {
            if (!Object.keys(values).includes(key)) {
                serverKeys.push(key);
            }
        });

        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.settings.retrieve',
                serverKeys, this.auth.token()
            ).subscribe(
                summary => {
                    this.cache[summary.name] =
                        values[summary.name] = summary.value;
                },
                err => reject,
                () => resolve(values)
            );
        });
    }

    removeItem(key: string): Promise<any> {
        return this.setItem(key, null);
    }
}

