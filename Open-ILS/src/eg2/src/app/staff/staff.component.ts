import {Component, OnInit, NgZone, HostListener} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';
import {AccessKeyInfoComponent} from '@eg/share/accesskey/accesskey-info.component';

const MFA_PATH = '/staff/mfa';
const LOGIN_PATH = '/staff/login';
const WS_BASE_PATH = '/staff/admin/workstation/workstations/';
const WS_MANAGE_PATH = '/staff/admin/workstation/workstations/manage';

@Component({
    templateUrl: 'staff.component.html',
    styleUrls: ['staff.component.css']
})

export class StaffComponent implements OnInit {

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private ngLocation: Location,
        private zone: NgZone,
        private net: NetService,
        private auth: AuthService,
        private keys: AccessKeyService
    ) {}

    ngOnInit() {

        // Fires on all in-staff-app router navigation, but not initial
        // page load.
        this.router.events.subscribe(routeEvent => {
            if (routeEvent instanceof NavigationEnd) {
                // console.debug(`StaffComponent routing to ${routeEvent.url}`);
                this.preventForbiddenNavigation(routeEvent.url);
            }
        });

        // Redirect to the login page on any auth timeout events.
        this.net.authExpired$.subscribe(expireEvent => {

            // If the expired authtoken was identified locally (i.e.
            // in this browser tab) notify all tabs of imminent logout.
            if (!expireEvent.viaExternal) {
                this.auth.broadcastLogout();
            }

            console.debug('Auth session has expired. Redirecting to login');
            const url = this.router.url;

            // https://github.com/angular/angular/issues/18254
            // When a tab redirects to a login page as a result of
            // another tab broadcasting a logout, ngOnInit() fails to
            // fire in the login component, until the user interacts
            // with the page.  Fix it by wrapping it in zone.run().
            // This is the only navigate() where I have seen this happen.
            this.zone.run(() => {
                this.router.navigate([LOGIN_PATH], {queryParams: {routeTo: url}});
            });
        });

        this.route.data.subscribe((data: {staffResolver: any}) => {
            // Data fetched via StaffResolver is available here.
        });
    }

    /**
     * Prevent the user from leaving the login page when they don't have
     * a valid authoken.
     *
     * Prevent the user from leaving the workstation admin page when
     * they don't have a valid workstation.
     *
     * This does not verify auth tokens with the server on every route,
     * because that would be overkill.  This is only here to keep
     * people boxed in with their authenication state was already
     * known to be less then 100%.
     */
    preventForbiddenNavigation(url: string): void {

        // No auth checks needed for login page.
        if (url.startsWith(LOGIN_PATH)) {
            return;
        }

        // We lost our authtoken, go back to the login page.
        if (!this.auth.token()) {
            this.router.navigate([LOGIN_PATH]);
        }

        // No auth checks needed for MFA page.
        if (url.startsWith(MFA_PATH)) {
            return;
        }

        // Provisional tokens require MFA
        if (this.auth.provisional()) {
            this.router.navigate([MFA_PATH]);
            return;
        }

        // No workstation checks needed for workstation admin page.
        if (url.startsWith(WS_BASE_PATH)) {
            return;
        }

        if (this.auth.workstationState !== AuthWsState.VALID) {
            this.router.navigate([WS_MANAGE_PATH]);
        }
    }

    /**
     * Listen for keyboard events here -- the root directive --  and pass
     * events down to the key service for processing.
     */
    @HostListener('window:keydown', ['$event']) onKeyDown(evt: KeyboardEvent) {
        this.keys.fire(evt);
    }

    /**
     * Make sure to fire the contextmenu Event on Shift+F10
     */
    fireContextMenuEvent(): void {
        const event = new MouseEvent('contextmenu', {
            bubbles: true,
            cancelable: false,
            view: window,
            button: 2,
            buttons: 0,
        });
        document.activeElement.dispatchEvent(event);
    }

    /*
    @ViewChild('egAccessKeyInfo')
    private keyComponent: AccessKeyInfoComponent;
    */

}

