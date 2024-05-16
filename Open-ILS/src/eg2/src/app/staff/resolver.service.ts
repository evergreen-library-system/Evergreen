import {Injectable} from '@angular/core';
import {Location} from '@angular/common';
import {Observable, Observer, of} from 'rxjs';
import {Router, Resolve, RouterStateSnapshot,
    ActivatedRoute, ActivatedRouteSnapshot} from '@angular/router';
import {StoreService} from '@eg/core/store.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {OrgService} from '@eg/core/org.service';
import {FormatService} from '@eg/core/format.service';
import {HatchService} from '@eg/core/hatch.service';

const LOGIN_PATH = '/staff/login';
const MFA_PATH = '/staff/mfa';
const WS_MANAGE_PATH = '/staff/admin/workstation/workstations/manage';

// Define these at the staff application level so they will be honored
// regardless of which interface is loaded / reloaded / etc.
const STAFF_LOGIN_SESSION_KEYS = [
    'eg.circ.patron_hold_target',
    'eg.catalog.recent_searches',
    'eg.circ.recent_patrons'
];

/**
 * Load data used by all staff modules.
 */
@Injectable()
export class StaffResolver implements Resolve<Observable<any>> {

    // Tracks the primary resolve observable.
    observer: Observer<any>;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private ngLocation: Location,
        private hatch: HatchService,
        private store: StoreService,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private perm: PermService,
        private format: FormatService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Observable<any> {

        this.hatch.connect();

        STAFF_LOGIN_SESSION_KEYS.forEach(
            key => this.store.addLoginSessionKey(key));

        // Staff cookies stay in /$base/staff/
        // NOTE: storing session data at '/' so it can be shared by
        // Angularjs apps.
        this.store.loginSessionBasePath = '/';
        // ^-- = this.ngLocation.prepareExternalUrl('/staff');

        // Not sure how to get the path without params... using this for now.
        const path = state.url.split('?')[0];
        if (path === '/staff/login' || path === '/staff/login-not-allowed') {
            return of(true);
        }

        const observable: Observable<any>
            = new Observable(o => this.observer = o);

        this.auth.testAuthToken().then(
            tokenOk => {
                this.confirmStaffPerms().then(
                    hasPerms => {
                        this.auth.verifyWorkstation().then(
                            wsOk => {
                                this.loadStartupData()
                                    .then(ok => {
                                    // Resolve observable must emit /something/
                                        this.observer.next(true);
                                        this.observer.complete();
                                    });
                            },
                            wsNotOk => this.handleInvalidWorkstation(path)
                        );
                    },
                    hasNotPerms => {
                        this.router.navigate(['/staff/login-not-allowed']);
                        this.observer.error('User does not have staff permissions');
                    }
                );
            },
            tokenNotOk => this.handleInvalidToken(state)
        );

        return observable;
    }


    // Confirm the user has the STAFF_LOGIN permission anywhere before
    // allowing the staff sub-tree to load. This will prevent users
    // with valid, non-staff authtokens from attempting to connect and
    // subsequently getting redirected to the workstation admin page
    // (since they won't have a valid WS either).
    confirmStaffPerms(): Promise<any> {
        return new Promise((resolve, reject) => {
            this.perm.hasWorkPermAt(['STAFF_LOGIN']).then(
                permMap => {
                    if (permMap.STAFF_LOGIN.length) {
                        resolve('perm check OK');
                    } else {
                        reject('perm check faield');
                    }
                }
            );
        });
    }


    // A page that's not the login page was requested without a
    // valid auth token.  Send the caller back to the login page.
    handleInvalidToken(state: RouterStateSnapshot): void {
        if (this.auth.provisional()) {
            console.debug('StaffResolver: authtoken is provisional, MFA required');
            // We have a provisional token, but we need to upgrade it. Send
            // the user to the MFA config-or-choose UI.

            const path = state.url.split('?')[0];
            if (path !== MFA_PATH) {
                // Redirect to MFA if we're not already on our way there
                this.router.navigate([MFA_PATH], {queryParams: {routeTo: state.url}});
                this.observer.complete();
            } else {
                // If we are, however, we're actually fine.  Proceed.
                this.observer.next(true);
                this.observer.complete();
            }
        } else {
            console.debug('StaffResolver: authtoken is not valid');
            // state.url is the eg2 path, not a full URL.
            this.router.navigate([LOGIN_PATH], {queryParams: {routeTo: state.url}});
            this.observer.error('invalid or no auth token');
        }
    }

    handleInvalidWorkstation(path: string): void {

        if (path.startsWith(WS_MANAGE_PATH)) {
            // user is navigating to the WS admin page.
            this.observer.next(true);
            // Resolve observable must emit /something/
            this.observer.complete();
        } else {
            this.router.navigate([WS_MANAGE_PATH]);
            this.observer.error(`Auth session linked to no
                workstation or a workstation unknown to this browser`);
        }
    }

    /**
     * Fetches data common to all staff interfaces.
     */
    loadStartupData(): Promise<any> {

        // Fetch settings needed globally.  This will cache the values
        // in the org service.
        return this.org.settings([
            'lib.timezone',
            'webstaff.format.dates',
            'webstaff.format.date_and_time',
            'ui.staff.max_recent_patrons',
            'circ.curbside', // navbar
            'ui.staff.angular_circ.enabled',
            'ui.staff.angular_catalog.enabled' // navbar
        ]).then(settings => {
            // Avoid clobbering defaults
            if (settings['lib.timezone']) {
                this.format.wsOrgTimezone = settings['lib.timezone'];
            }
            if (settings['webstaff.format.dates']) {
                this.format.dateFormat = settings['webstaff.format.dates'];
            }
            if (settings['webstaff.format.date_and_time']) {
                this.format.dateTimeFormat =
                    settings['webstaff.format.date_and_time'];
            }
            // TODO remove these once Angular Circ takes over.
            if (settings['ui.staff.angular_circ.enabled']) {
                return this.perm.hasWorkPermHere(['ACCESS_ANGULAR_CIRC']);
            }
        });
    }
}

