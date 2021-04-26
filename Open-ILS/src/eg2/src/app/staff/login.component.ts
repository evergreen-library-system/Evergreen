import {Component, OnInit, Renderer2} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';
import {OrgService} from '@eg/core/org.service';
import {OfflineService} from '@eg/staff/share/offline.service';

// Direct users to the AngJS splash page when no routeTo is provided.
const SPLASH_PAGE_PATH = '/eg/staff/splash';

@Component({
  templateUrl : './login.component.html'
})
export class StaffLoginComponent implements OnInit {

    workstations: any[];
    loginFailed: boolean;
    routeTo: string;

    args = {
      username : '',
      password : '',
      workstation : '',
      type : 'staff'
    };

    constructor(
      private router: Router,
      private route: ActivatedRoute,
      private ngLocation: Location,
      private renderer: Renderer2,
      private auth: AuthService,
      private org: OrgService,
      private store: StoreService,
      private offline: OfflineService
    ) {}

    ngOnInit() {
        this.routeTo = this.route.snapshot.queryParamMap.get('routeTo');

        if (this.routeTo) {
            if (this.routeTo.match(/^[a-z]+:\/\//i)) {
                console.warn(
                    'routeTo must contain only path information: ', this.routeTo);
                this.routeTo = null;
            }
        }

        // clear out any stale auth data
        this.auth.logout();

        // Focus username
        this.renderer.selectRootElement('#username').focus();

        this.store.getWorkstations()
        .then(wsList => {
            this.workstations = wsList;
            return this.store.getDefaultWorkstation();
        }).then(def => {
            this.args.workstation = def;
            this.applyWorkstation();
        });
    }

    applyWorkstation() {
        const wanted = this.route.snapshot.queryParamMap.get('workstation');
        if (!wanted) { return; } // use the default

        const exists = this.workstations.filter(w => w.name === wanted)[0];
        if (exists) {
            this.args.workstation = wanted;
        } else {
            console.error(`Unknown workstation requested: ${wanted}`);
        }
    }

    handleSubmit() {

        // post-login URL
        let url: string = this.routeTo || SPLASH_PAGE_PATH;

        // prevent sending the user back to the login page
        if (url.match('/staff/login')) { url = SPLASH_PAGE_PATH; }

        const workstation: string = this.args.workstation;

        this.loginFailed = false;
        this.auth.login(this.args).then(
            ok => {

                if (this.auth.workstationState === AuthWsState.NOT_FOUND_SERVER) {
                    // User attempted to login with a workstation that is
                    // unknown to the server. Redirect to the WS admin page.
                    // Reset the WS state to avoid looping back to WS removal
                    // page before the new workstation can be activated.
                    this.auth.workstationState = AuthWsState.PENDING;
                    this.router.navigate(
                        [`/staff/admin/workstation/workstations/remove/${workstation}`]);

                } else {

                    this.offline.refreshOfflineData()
                    // Initial login clears cached org unit settings.
                    .then(_ => this.org.clearCachedSettings())
                    .then(_ => {

                        // Force reload of the app after a successful login.
                        // This allows the route resolver to re-run with a
                        // valid auth token and workstation.
                        window.location.href =
                            this.ngLocation.prepareExternalUrl(url);
                    });
                }
            },
            notOk => {
                this.loginFailed = true;
            }
        );
    }
}



