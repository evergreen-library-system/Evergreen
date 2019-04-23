import {Injectable} from '@angular/core';
import {Location} from '@angular/common';
import {Observable, Observer, of} from 'rxjs';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRoute, ActivatedRouteSnapshot} from '@angular/router';
import {StoreService} from '@eg/core/store.service';
import {NetService} from '@eg/core/net.service';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {OrgService} from '@eg/core/org.service';
import {FormatService} from '@eg/core/format.service';
import {HatchService} from '@eg/core/hatch.service';

const LOGIN_PATH = '/staff/login';
const WS_MANAGE_PATH = '/staff/admin/workstation/workstations/manage';

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

        // Staff cookies stay in /$base/staff/
        // NOTE: storing session data at '/' so it can be shared by
        // Angularjs apps.
        this.store.loginSessionBasePath = '/';
        // ^-- = this.ngLocation.prepareExternalUrl('/staff');

        // Not sure how to get the path without params... using this for now.
        const path = state.url.split('?')[0];
        if (path === '/staff/login') {
            return of(true);
        }

        const observable: Observable<any>
            = Observable.create(o => this.observer = o);

        this.auth.testAuthToken().then(
            tokenOk => {
                this.confirmStaffPerms().then(
                    hasPerms => {
                        this.auth.verifyWorkstation().then(
                            wsOk => {
                                this.loadStartupData()
                                .then(ok => this.observer.complete());
                            },
                            wsNotOk => this.handleInvalidWorkstation(path)
                        );
                    },
                    hasNotPerms => {
                        this.observer.error(
                            'User does not have staff permissions');
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
        console.debug('StaffResolver: authtoken is not valid');
        this.auth.redirectUrl = state.url;
        this.router.navigate([LOGIN_PATH]);
        this.observer.error('invalid or no auth token');
    }

    handleInvalidWorkstation(path: string): void {

        if (path.startsWith(WS_MANAGE_PATH)) {
            // user is navigating to the WS admin page.
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
    loadStartupData(): Promise<void> {

        // Fetch settings needed globally.  This will cache the values
        // in the org service.
        return this.org.settings([
            'lib.timezone',
            'webstaff.format.dates',
            'webstaff.format.date_and_time',
            'ui.staff.max_recent_patrons',
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
        });
    }
}

