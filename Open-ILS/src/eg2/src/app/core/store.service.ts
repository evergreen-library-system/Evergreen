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
        'eg.auth.token.oc',
        'eg.auth.time.oc'
    ];

    constructor(
        private cookieService: CookieService) {
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
        this.loginSessionKeys.push(key);
    }

    setLocalItem(key: string, val: any, isJson?: boolean): void {
        if (!isJson) {
            val = JSON.stringify(val);
        }
        window.localStorage.setItem(key, val);
    }

    setSessionItem(key: string, val: any, isJson?: boolean): void {
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

    getLocalItem(key: string): any {
        return this.parseJson(window.localStorage.getItem(key));
    }

    getSessionItem(key: string): any {
        return this.parseJson(window.sessionStorage.getItem(key));
    }

    getLoginSessionItem(key: string): any {
        return this.parseJson(this.cookieService.get(key));
    }

    removeLocalItem(key: string): void {
        window.localStorage.removeItem(key);
    }

    removeSessionItem(key: string): void {
        window.sessionStorage.removeItem(key);
    }

    removeLoginSessionItem(key: string): void {
        this.cookieService.remove(key, {path : this.loginSessionBasePath});
    }

    clearLoginSessionItems(): void {
        this.loginSessionKeys.forEach(
            key => this.removeLoginSessionItem(key)
        );
    }
}

