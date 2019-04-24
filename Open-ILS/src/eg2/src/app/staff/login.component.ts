import {Component, OnInit, Renderer2} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';

@Component({
  templateUrl : './login.component.html'
})

export class StaffLoginComponent implements OnInit {

    workstations: any[];

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
      private store: StoreService
    ) {}

    ngOnInit() {
        // clear out any stale auth data
        this.auth.logout();

        // Focus username
        this.renderer.selectRootElement('#username').focus();

        this.workstations = this.store.getLocalItem('eg.workstation.all');
        this.args.workstation =
            this.store.getLocalItem('eg.workstation.default');
        this.applyWorkstation();
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
        let url: string = this.auth.redirectUrl || '/staff/splash';

        // prevent sending the user back to the login page
        if (url.startsWith('/staff/login')) {
            url = '/staff/splash';
        }

        const workstation: string = this.args.workstation;

        this.auth.login(this.args).then(
            ok => {
                this.auth.redirectUrl = null;

                if (this.auth.workstationState === AuthWsState.NOT_FOUND_SERVER) {
                    // User attempted to login with a workstation that is
                    // unknown to the server. Redirect to the WS admin page.
                    // Reset the WS state to avoid looping back to WS removal
                    // page before the new workstation can be activated.
                    this.auth.workstationState = AuthWsState.PENDING;
                    this.router.navigate(
                        [`/staff/admin/workstation/workstations/remove/${workstation}`]);
                } else {
                    // Force reload of the app after a successful login.
                    // This allows the route resolver to re-run with a
                    // valid auth token and workstation.
                    window.location.href =
                        this.ngLocation.prepareExternalUrl(url);
                }
            },
            notOk => {
                // indicate failure in the UI.
            }
        );
    }
}



