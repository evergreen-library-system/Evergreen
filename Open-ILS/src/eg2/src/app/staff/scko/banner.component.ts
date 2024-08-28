import {Component, OnInit, AfterViewInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';
import {SckoService, ActionContext} from './scko.service';
import {OrgService} from '@eg/core/org.service';
import {HatchService} from '@eg/core/hatch.service';
import {ForceReloadService} from '@eg/share/util/force-reload.service';

const FOCUS_DELAY = 50;

@Component({
    selector: 'eg-scko-banner',
    templateUrl: 'banner.component.html'
})

export class SckoBannerComponent implements OnInit, AfterViewInit {

    workstations: any[];
    workstationNotFound = false;

    patronUsername: string;
    patronPassword: string;

    staffUsername: string;
    staffPassword: string;
    staffWorkstation: string;
    staffLoginFailed = false;
    missingRequiredWorkstation = false;

    itemBarcode: string;

    constructor(
        private route: ActivatedRoute,
        private store: StoreService,
        private auth: AuthService,
        private org: OrgService,
        private hatch: HatchService,
        public scko: SckoService,
        private forceReload: ForceReloadService
    ) {}

    ngOnInit() {
        this.staffUsername = '';
        this.staffPassword = '';
        this.patronUsername = '';
        this.patronPassword = '';

        this.hatch.connect();

        this.store.getWorkstations()
            .then(wsList => {
                this.workstations = wsList;
                return this.store.getDefaultWorkstation();
            }).then(def => {
                this.staffWorkstation = def;
                this.applyWorkstation();
            });
    }

    ngAfterViewInit() {
        if (this.auth.token()) {
            this.focusNode('patron-username');
        } else {
            this.focusNode('staff-username');
        }

        this.scko.focusBarcode.subscribe(_ => this.focusNode('item-barcode'));
    }

    focusNode(id: string) {
        setTimeout(() => {
            const node = document.getElementById(id);
            if (node) {
                (node as HTMLInputElement).select();
                (node as HTMLInputElement).focus();
            }
        }, FOCUS_DELAY);
    }

    applyWorkstation() {
        const wanted = this.route.snapshot.queryParamMap.get('workstation');
        if (!wanted) { return; } // use the default

        const exists = this.workstations.filter(w => w.name === wanted)[0];
        if (exists) {
            this.staffWorkstation = wanted;
        } else {
            console.error(`Unknown workstation requested: ${wanted}`);
        }
    }

    submitStaffLogin(): Promise<void> {

        this.staffLoginFailed = false;

        const args = {
            type: 'staff',
            agent: 'selfcheck',
            username: this.staffUsername,
            password: this.staffPassword,
            workstation: this.staffWorkstation
        };

        this.staffLoginFailed = false;
        this.workstationNotFound = false;

        return this.auth.login(args).then(
            ok => {

                if (this.auth.workstationState === AuthWsState.NOT_FOUND_SERVER) {
                    this.staffLoginFailed = true;
                    this.workstationNotFound = true;

                } else {
                    this.org.settings('circ.selfcheck.workstation_required', this.org.root().id(), true).then((settings) => {
                        if (settings['circ.selfcheck.workstation_required'] && !this.staffWorkstation) {
                            this.staffLoginFailed = true;
                            this.missingRequiredWorkstation = true;
                            this.auth.logout();
                        } else {
                            // Initial login clears cached org unit setting values
                            // and user/workstation setting values
                            this.org.clearCachedSettings().then(_ => {

                                // Force reload of the app after a successful login.
                                this.forceReload.reload('/staff/selfcheck');
                            });
                        }
                    });
                }
            },
            notOk => {
                this.staffLoginFailed = true;
            }
        );
    }

    submitPatronLogin() {
        this.patronUsername = (this.patronUsername || '').trim();
        this.scko.loadPatron(this.patronUsername, this.patronPassword)
            .finally(() => {

                if (this.scko.patronSummary === null) {

                    const ctx: ActionContext = {
                        username: this.patronUsername,
                        shouldPopup: true,
                        alertSound: 'error.scko.login_failed',
                        displayText: 'scko.error.login_failed'
                    };

                    this.scko.notifyPatron(ctx);

                } else {
                    this.focusNode('item-barcode');
                }

                this.patronUsername = '';
                this.patronPassword = '';
            });
    }

    submitItemBarcode() {
        this.scko.resetPatronTimeout();
        this.scko.checkout(this.itemBarcode);
        this.itemBarcode = '';
    }
}

