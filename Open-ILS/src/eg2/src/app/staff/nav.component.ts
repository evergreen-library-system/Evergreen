import {Component, OnInit, OnDestroy, QueryList, ViewChild, ViewChildren} from '@angular/core';
import {ActivatedRoute, Router} from '@angular/router';
import {Location} from '@angular/common';
import {Subscription} from 'rxjs';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {LocaleService} from '@eg/core/locale.service';
import {PrintService} from '@eg/share/print/print.service';
import {StoreService} from '@eg/core/store.service';
import {NetRequest, NetService} from '@eg/core/net.service';
import {OpChangeComponent} from '@eg/staff/share/op-change/op-change.component';
import {PermService} from '@eg/core/perm.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {NgbCollapseModule, NgbDropdown} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-staff-nav-bar',
    styleUrls: ['nav.component.css'],
    templateUrl: 'nav.component.html'
})

export class StaffNavComponent implements OnInit, OnDestroy {

    // Locales that have Angular staff translations
    locales: any[];
    currentLocale: any;

    // When active, show a link to the traditional staff catalog
    showTraditionalCatalog = true;
    showAngularAcq: boolean;
    curbsideEnabled: boolean;
    showAngularCirc = false;
    maxRecentPatrons = 1;

    // Menu toggle
    isMenuCollapsed = true;

    @ViewChild('navOpChange', {static: false}) opChange: OpChangeComponent;
    @ViewChild('confirmLogout', { static: true }) confirmLogout: ConfirmDialogComponent;
    @ViewChildren(NgbDropdown) dropdowns: QueryList<NgbDropdown>;
    permFailedSub: Subscription;

    constructor(
        private router: Router,
        private store: StoreService,
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
        private perm: PermService,
        private pcrud: PcrudService,
        private locale: LocaleService,
        private printer: PrintService
    ) {
        this.locales = [];
    }

    ngOnInit() {

        this.locale.supportedLocales().subscribe(
            l => this.locales.push(l),
            (err: unknown) => {},
            () => {
                this.currentLocale = this.locales.filter(
                    l => l.code() === this.locale.currentLocaleCode())[0];
            }
        );

        // NOTE: this can eventually go away.
        // Avoid attempts to fetch org settings if the user has not yet
        // logged in (e.g. this is the login page).
        if (this.user()) {
            // Note these are all pre-cached by our resolver.
            // Batching not required.
            this.org.settings('ui.staff.traditional_catalog.enabled')
                .then(settings => this.showTraditionalCatalog =
                Boolean(settings['ui.staff.traditional_catalog.enabled']));

            this.org.settings('circ.curbside')
                .then(settings => this.curbsideEnabled =
                Boolean(settings['circ.curbside']));

            this.org.settings('ui.staff.max_recent_patrons')
                .then(settings => this.maxRecentPatrons =
                settings['ui.staff.max_recent_patrons'] ?? 1);

            // Do we show the angular circ menu?
            // TODO remove these once Angular Circ takes over.
            const angSet = 'ui.staff.angular_circ.enabled';
            const angPerm = 'ACCESS_ANGULAR_CIRC';

            this.org.settings(angSet).then(s => {
                if (s[angSet]) {
                    return this.perm.hasWorkPermHere([angPerm])
                        .then(perms => perms[angPerm]);
                } else {
                    return false;
                }
            }).then(enable => this.showAngularCirc = enable);
        }

        // Wire up our op-change component as the general purpose
        // permission failed handler.
        this.net.permFailedHasHandler = true;
        this.permFailedSub =
            this.net.permFailed$.subscribe(
                (req: NetRequest) => this.opChange.escalateRequest(req));
    }

    ngOnDestroy() {
        if (this.permFailedSub) {
            this.permFailedSub.unsubscribe();
        }
    }

    user() {
        return this.auth.user() ? this.auth.user().usrname() : '';
    }

    user_id() {
        return this.auth.user() ? this.auth.user().id() : '';
    }

    workstation() {
        return this.auth.user() ? this.auth.workstation() : '';
    }

    ws_ou() {
        return this.auth.user() ? this.auth.user().ws_ou() : '';
    }

    setLocale(locale: any) {
        this.locale.setLocale(locale.code());
    }

    opChangeActive(): boolean {
        return this.auth.opChangeIsActive();
    }

    maybeLogout() {
        this.confirmLogout.open().subscribe(confirmed => {
            if (!confirmed) { return; }

            this.logout();
        });
    }

    // Broadcast to all tabs that we're logging out.
    // Redirect to the login page, which performs the remaining
    // logout duties.
    logout(): void {
        this.auth.broadcastLogout();
        this.router.navigate(['/staff/login']);
    }

    reprintLast() {
        this.printer.reprintLast();
    }

    retrieveLastRecord() {
        const recId = this.store.getLocalItem('eg.cat.last_record_retrieved');
        if (recId) {
            this.router.navigate(['/staff/catalog/record/' + recId]);
        }
    }

    closeDropdowns() {
        this.dropdowns?.forEach(x => x.close());
    }
}


