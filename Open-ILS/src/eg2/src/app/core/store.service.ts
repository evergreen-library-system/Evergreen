/**
 * Store and retrieve data from various sources.
 *
 * Data Types:
 * 1. LocalItem: Stored in window.localStorage and persist indefinitely.
 * 2. SessionItem: Stored in window.sessionStorage and persist until
 *    the end of the current browser tab/window.  Data is only available
 *    to the tab/window where the data was set.
 * 3. LoginItem: Stored as session cookies and persist until the browser
 *    is closed.  These values are avalable to all browser windows/tabs.
 */
import {Injectable} from '@angular/core';
import {CookieService} from 'ngx-cookie';
import {HatchService} from './hatch.service';

const WS_ALL_KEY = 'eg.workstation.all';
const WS_DEF_KEY = 'eg.workstation.default';

@Injectable({providedIn: 'root'})
export class StoreService {

    // Base path for cookie-based storage.
    // Useful for limiting cookies to subsections of the application.
    // Store cookies globally by default.
    // Note cookies shared with /eg/staff must be stored at "/"
    loginSessionBasePath = '/';

    // Set of keys whose values should disappear at logout.
    loginSessionKeys: string[] = [
        'eg.auth.token',
        'eg.auth.time',
        'eg.auth.token.provisional',
        'eg.auth.time.provisional',
        'eg.auth.token.oc',
        'eg.auth.time.oc'
    ];

    constructor(
        private cookieService: CookieService,
        private hatch: HatchService) {
    }

    private parseJson(valJson: string): any {
        if (valJson === undefined || valJson === null || valJson === '') {
            return null;
        }
        try {
            return JSON.parse(valJson);
        } catch (E) {
            console.error(`Failure to parse JSON: ${E} => ${valJson}`);
            return null;
        }
    }

    /**
     * Add a an app-local login session key
     */
    addLoginSessionKey(key: string): void {
        if (!this.loginSessionKeys.includes(key)) {
            this.loginSessionKeys.push(key);
        }
    }

    setLocalItem(key: string, val: any, isJson?: boolean): void {
        if (!isJson) {
            val = JSON.stringify(val);
        }
        window.localStorage.setItem(key, val);
    }

    setSessionItem(key: string, val: any, isJson?: boolean): void {
        console.log(`Setting session item: key=${key}, value=`, val, `isJson=${isJson}`);
        if (!isJson) {
            val = JSON.stringify(val);
        }
        window.sessionStorage.setItem(key, val);
    }

    setLoginSessionItem(key: string, val: any, isJson?: boolean): void {
        if (!isJson) {
            val = JSON.stringify(val);
        }
        this.cookieService.put(key, val,
            {path : this.loginSessionBasePath, secure: true});
    }

    setWorkstations(val: any, isJson?: boolean): Promise<any> {
        if (this.hatch.isAvailable) {
            return this.hatch.setItem(WS_ALL_KEY, val).then(
                ok => {
                    // When clearing workstations, remove the default.
                    if (!val || val.length === 0) {
                        return this.hatch.removeItem(WS_DEF_KEY);
                    }
                }
            );
        } else {
            return Promise.resolve(
                this.setLocalItem(WS_ALL_KEY, val, isJson));
        }
    }

    setDefaultWorkstation(val: string, isJson?: boolean): Promise<any> {
        if (this.hatch.isAvailable) {
            return this.hatch.setItem(WS_DEF_KEY, val);
        } else {
            return Promise.resolve(
                this.setLocalItem(WS_DEF_KEY, val, isJson));
        }
    }

    getLocalItem(key: string): any {
        return this.parseJson(window.localStorage.getItem(key));
    }

    getLocalItemNames(): string[] {
        const keys = [];
        for (let i = 0; i < window.localStorage.length ; i++ ) {
            keys.push(window.localStorage.key(i));
        }
        return keys;
    }

    getSessionItem(key: string): any {
        return this.parseJson(window.sessionStorage.getItem(key));
    }

    getLoginSessionItem(key: string): any {
        return this.parseJson(this.cookieService.get(key));
    }

    getWorkstations(): Promise<any> {
        if (this.hatch.isAvailable) {
            return this.mergeWorkstations().then(ok => {
                this.removeLocalItem(WS_ALL_KEY);
                return this.hatch.getItem(WS_ALL_KEY);
            });
        } else {
            return Promise.resolve(this.getLocalItem(WS_ALL_KEY));
        }
    }

    // See if any workstatoins are stored in local storage.  If so, also
    // see if we have any stored in Hatch.  If both, merged workstations
    // from localStorage in Hatch storage, skipping any whose name
    // collide with a workstation in Hatch.  If none exist in Hatch,
    // copy the localStorage workstations over wholesale.
    mergeWorkstations(): Promise<any> {
        const existing = this.getLocalItem(WS_ALL_KEY);

        if (!existing || existing.length === 0) {
            return Promise.resolve();
        }

        return this.hatch.getItem(WS_ALL_KEY).then(inHatch => {

            if (!inHatch || inHatch.length === 0) {
                // Nothing to merge, copy the data over directly
                return this.hatch.setItem('eg.workstation.all', existing);
            }

            const addMe: any = [];
            existing.forEach(ws => {
                const match = inHatch.filter(w => w.name === ws.name)[0];
                if (!match) {
                    console.log(
                        'Migrating workstation from local storage to hatch: '
                        + ws.name
                    );
                    addMe.push(ws);
                }
            });
            inHatch = inHatch.concat(addMe);
            return this.hatch.setItem(WS_ALL_KEY, inHatch);
        });
    }

    getDefaultWorkstation(): Promise<any> {
        if (this.hatch.isAvailable) {
            return this.hatch.getItem(WS_DEF_KEY).then(name => {
                if (name) {
                    // We have a default in Hatch, remove any lingering
                    // value from localStorage.
                    this.removeLocalItem(WS_DEF_KEY);
                    return name;
                } else {
                    // Nothing in Hatch, see if we have a localStorage
                    // value to migrate to Hatch
                    name = this.getLocalItem(WS_DEF_KEY);
                    if (name) {
                        console.debug(
                            'Migrating default workstation to Hatch ' + name);
                        return this.hatch.setItem(WS_DEF_KEY, name)
                            .then(ok => name);
                    } else {
                        return null;
                    }
                }
            });
        } else {
            return Promise.resolve(this.getLocalItem(WS_DEF_KEY));
        }
    }

    removeLocalItem(key: string): void {
        window.localStorage.removeItem(key);
    }

    removeLocalItems(keys: string[]): void {
        keys.forEach((key) => this.removeLocalItem(key));
    }

    removeSessionItem(key: string): void {
        window.sessionStorage.removeItem(key);
    }

    removeLoginSessionItem(key: string): void {
        this.cookieService.remove(key, {path : this.loginSessionBasePath});
    }

    removeDefaultWorkstation(val: string, isJson?: boolean): Promise<any> {
        if (this.hatch.isAvailable) {
            return this.hatch.removeItem(WS_DEF_KEY);
        } else {
            return Promise.resolve(
                this.removeLocalItem(WS_DEF_KEY));
        }
    }


    clearLoginSessionItems(): void {
        this.loginSessionKeys.forEach(
            key => this.removeLoginSessionItem(key)
        );
    }
}

