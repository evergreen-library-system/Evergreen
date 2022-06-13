/* eslint-disable no-magic-numbers */
import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from './net.service';
import {EventService, EgEvent} from './event.service';
import {IdlService, IdlObject} from './idl.service';
import {StoreService} from './store.service';

// Not universally available.
declare var BroadcastChannel; // eslint-disable-line no-var

// Models a login instance.
class AuthUser {
    user:        IdlObject; // actor.usr (au) object
    workstation: string; // workstation name
    token:       string;
    authtime:    number;
    provisional: boolean;
    mfaAllowed:  boolean;

    constructor(token: string, authtime: number, workstation?: string, provisional?: boolean, mfaAllowed?: boolean) {
        this.token = token;
        this.workstation = workstation;
        this.authtime = authtime;
        this.provisional = provisional;
        this.mfaAllowed = mfaAllowed;
    }
}

// Params required for calling the login() method.
interface AuthLoginArgs {
    username: string;
    password: string;
    type: string;
    workstation?: string;
}

// eslint-disable-next-line no-shadow
export enum AuthWsState {
    PENDING,
    NOT_USED,
    NOT_FOUND_SERVER,
    NOT_FOUND_LOCAL,
    VALID
}

@Injectable({providedIn: 'root'})
export class AuthService {

    // Override this to store authtokens, etc. in a different location
    authDomain = 'eg.auth';

    private authChannel: any;

    private activeUser: AuthUser = null;

    workstationState: AuthWsState = AuthWsState.PENDING;

    // reference to active auth validity setTimeout handler.
    pollTimeout: any;

    constructor(
        private egEvt: EventService,
        private net: NetService,
        private store: StoreService
    ) {

        // BroadcastChannel is not yet defined in PhantomJS and elsewhere
        this.authChannel = (typeof BroadcastChannel === 'undefined') ?
            {} : new BroadcastChannel('eg.auth');
    }

    // Returns true if we are currently in op-change mode.
    opChangeIsActive(): boolean {
        return Boolean(this.store.getLoginSessionItem(`${this.authDomain}.time.oc`));
    }

    // - Accessor functions always refer to the active user.

    user(): IdlObject {
        return this.activeUser ? this.activeUser.user : null;
    }

    // Workstation name.
    workstation(): string {
        return this.activeUser ? this.activeUser.workstation : null;
    }

    token(): string {
        return this.activeUser ? this.activeUser.token : null;
    }

    authtime(): number {
        return this.activeUser ? this.activeUser.authtime : 0;
    }

    provisional(): boolean {
        return this.activeUser ? this.activeUser.provisional : false;
    }

    mfaAllowed(): boolean {
        return this.activeUser ? this.activeUser.mfaAllowed : false;
    }

    // NOTE: NetService emits an event if the auth session has expired.
    // This only rejects when no authtoken is found.
    testAuthToken(): Promise<any> {

        if (!this.activeUser?.token) {
            // Only necessary on new page loads.  During op-change,
            // for example, we already have an activeUser.
            this.activeUser = new AuthUser(
                this.store.getLoginSessionItem(`${this.authDomain}.token`),
                this.store.getLoginSessionItem(`${this.authDomain}.time`)
            );
        }

        if (!this.activeUser?.token) { // let's try to get a provisional token
            this.activeUser = new AuthUser(
                this.store.getLoginSessionItem('eg.auth.token.provisional'),
                this.store.getLoginSessionItem('eg.auth.time.provisional'),
                null, true, true
            );
        }

        if (!this.token()) {
            return Promise.reject('no authtoken');
        }

        if (this.provisional()) {
            return Promise.reject('provisional authtoken');
        }

        return this.net.request(
            'open-ils.auth',
            'open-ils.auth.session.retrieve', this.token()
        ).toPromise().then(user => {
            // NetService interceps NO_SESSION events.
            // We can only get here if the session is valid.
            this.activeUser.user = user;
            this.listenForLogout();
            this.sessionPoll();
        }).then(() => {
            return this.net.request(
                'open-ils.auth_mfa',
                'open-ils.auth_mfa.allowed_for_token',
                this.token()
            ).toPromise().then(res => {
                // cache MFA allowed-ness whenever we have to fetch the session
                this.activeUser.mfaAllowed = Number(res) === 1;
            });
        });
    }

    loginApi(args: AuthLoginArgs, service: string,
        method: string, isOpChange?: boolean): Promise<void> {

        return this.net.request(service, method, args)
            .toPromise().then(res => {
                return this.handleLoginResponse(
                    args, this.egEvt.parse(res), isOpChange);
            });
    }

    login(args: AuthLoginArgs, isOpChange?: boolean): Promise<void> {
        let service = 'open-ils.auth';
        let method = 'open-ils.auth.login';

        if (isOpChange && this.opChangeIsActive()) {
            // Enforce one op-change at a time.
            this.undoOpChange();
        }

        return this.net.request(
            'open-ils.auth_proxy',
            'open-ils.auth_proxy.enabled')
            .toPromise().then(
                enabled => {
                    if (Number(enabled) === 1) {
                        service = 'open-ils.auth_proxy';
                        method = 'open-ils.auth_proxy.login';
                    }
                    return this.loginApi(args, service, method, isOpChange);
                },
                error => {
                // auth_proxy check resulted in a low-level error.
                // Likely the service is not running.  Fall back to
                // standard auth login.
                    return this.loginApi(args, service, method, isOpChange);
                }
            );
    }

    handleLoginResponse(
        args: AuthLoginArgs, evt: EgEvent, isOpChange: boolean): Promise<void> {

        switch (evt.textcode) {
            case 'SUCCESS':
                return this.handleLoginOk(args, evt, isOpChange);

            case 'WORKSTATION_NOT_FOUND':
                console.error(`No such workstation "${args.workstation}"`);
                this.workstationState = AuthWsState.NOT_FOUND_SERVER;
                delete args.workstation;
                return this.login(args, isOpChange);

            default:
                console.error(`Login returned unexpected event: ${evt}`);
                return Promise.reject('login failed');
        }
    }

    provisionalTokenUpgraded(): Promise<any> {
        if (this.provisional()) {
            this.activeUser = new AuthUser(
                this.store.getLoginSessionItem('eg.auth.token.provisional'),
                this.store.getLoginSessionItem('eg.auth.time.provisional'),
                this.activeUser.workstation, false
            );
            this.activeUser.mfaAllowed = true;
            this.store.removeLoginSessionItem('eg.auth.token.provisional');
            this.store.removeLoginSessionItem('eg.auth.time.provisional');
            this.store.setLoginSessionItem('eg.auth.token', this.token());
            this.store.setLoginSessionItem('eg.auth.time', this.authtime());
        }
        // Re-fetch the user.
        return this.testAuthToken();
    }

    // Stash the login data
    handleLoginOk(args: AuthLoginArgs, evt: EgEvent, isOpChange: boolean): Promise<void> {

        if (isOpChange) {
            this.store.setLoginSessionItem(`${this.authDomain}.token.oc`, this.token());
            this.store.setLoginSessionItem(`${this.authDomain}.time.oc`, this.authtime());
        }

        this.activeUser = new AuthUser(
            evt.payload.authtoken,
            evt.payload.authtime,
            args.workstation,
            !!evt.payload.provisional,
            !!evt.payload.provisional
        );

        if (this.provisional()) {
            this.store.setLoginSessionItem(`${this.authDomain}.token.provisional`, this.token());
            this.store.setLoginSessionItem(`${this.authDomain}.time.provisional`, this.authtime());
        } else {
            this.store.setLoginSessionItem(`${this.authDomain}.token`, this.token());
            this.store.setLoginSessionItem(`${this.authDomain}.time`, this.authtime());
        }

        return Promise.resolve();
    }

    undoOpChange(): Promise<any> {
        if (this.opChangeIsActive()) {
            this.deleteSession();
            this.activeUser = new AuthUser(
                this.store.getLoginSessionItem(`${this.authDomain}.token.oc`),
                this.store.getLoginSessionItem(`${this.authDomain}.time.oc`),
                this.activeUser.workstation
            );
            this.store.removeLoginSessionItem(`${this.authDomain}.token.oc`);
            this.store.removeLoginSessionItem(`${this.authDomain}.time.oc`);
            this.store.setLoginSessionItem(`${this.authDomain}.token`, this.token());
            this.store.setLoginSessionItem(`${this.authDomain}.time`, this.authtime());
        }
        // Re-fetch the user.
        return this.testAuthToken();
    }

    /**
     * Listen for logout events initiated by other browser tabs.
     */
    listenForLogout(): void {
        if (this.authChannel.onmessage) {
            return;
        }

        this.authChannel.onmessage = (e) => {
            console.debug(
                `received eg.auth broadcast ${JSON.stringify(e.data)}`);

            if (e.data.action === 'logout') {
                // Logout will be handled by the originating tab.
                // We just need to clear tab-local memory.
                this.cleanup();
                this.net.authExpired$.emit({viaExternal: true});
            }
        };
    }

    /**
     * Force-check the validity of the authtoken on occasion.
     * This allows us to redirect an idle staff client back to the login
     * page after the session times out.  Otherwise, the UI would stay
     * open with potentially sensitive data visible.
     * TODO: What is the practical difference (for a browser) between
     * checking auth validity and the ui.general.idle_timeout setting?
     * Does that setting serve a purpose in a browser environment?
     */
    sessionPoll(): void {

        // add a 5 second delay to give the token plenty of time
        // to expire on the server.
        let pollTime = this.authtime() * 1000 + 5000;

        if (pollTime < 60000) {
            // Never poll more often than once per minute.
            pollTime = 60000;
        } else if (pollTime > 2147483647) {
            // Avoid integer overflow resulting in $timeout() effectively
            // running with timeout=0 in a loop.
            pollTime = 2147483647;
        }

        this.pollTimeout = setTimeout(() => {
            this.net.request(
                'open-ils.auth',
                'open-ils.auth.session.retrieve',
                this.token(),
                0, // return extra auth details, unneeded here.
                1  // avoid extending the auth timeout

            // NetService intercepts NO_SESSION events.
            // If the promise resolves, the session is valid.
            ).subscribe(
                user => this.sessionPoll(),
                (err: unknown)  => console.warn('auth poll error: ' + err)
            );

        }, pollTime);
    }


    // Resolves if login workstation matches a workstation known to this
    // browser instance.  No attempt is made to see if the workstation
    // is present on the server.  That happens at login time.
    verifyWorkstation(): Promise<void> {

        if (!this.user()) {
            this.workstationState = AuthWsState.PENDING;
            return Promise.reject('Cannot verify workstation without user');
        }

        if (!this.user().wsid()) {
            this.workstationState = AuthWsState.NOT_USED;
            return Promise.reject('User has no workstation ID to verify');
        }

        return new Promise((resolve, reject) => {
            return this.store.getWorkstations().then(workstations => {

                if (workstations) {
                    const ws = workstations.filter(
                        w => Number(w.id) === Number(this.user().wsid()))[0];

                    if (ws) {
                        this.activeUser.workstation = ws.name;
                        this.workstationState = AuthWsState.VALID;
                        return resolve();
                    }
                }

                this.workstationState = AuthWsState.NOT_FOUND_LOCAL;
                reject();
            });
        });
    }

    deleteSession(): void {
        if (this.token()) {
            // note we have to subscribe to the net.request or it will
            // not fire -- observables only run when subscribed to.
            this.net.request(
                'open-ils.auth',
                'open-ils.auth.session.delete', this.token())
                .subscribe(x => {});
        }
    }

    // Tell all listening browser tabs that it's time to logout.
    // This should only be invoked by one tab.
    broadcastLogout(): void {
        console.debug('Notifying tabs of imminent auth token removal');
        this.authChannel.postMessage({action : 'logout'});
    }

    // Remove/reset session data
    cleanup(): void {
        this.activeUser = null;
        if (this.pollTimeout) {
            clearTimeout(this.pollTimeout);
            this.pollTimeout = null;
        }
    }

    // Invalidate server auth token and clean up.
    logout(): void {
        this.deleteSession();
        this.store.clearLoginSessionItems();
        this.cleanup();
    }
}
