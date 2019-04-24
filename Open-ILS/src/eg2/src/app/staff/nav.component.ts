import {Component, OnInit, ViewChild} from '@angular/core';
import {ActivatedRoute, Router} from '@angular/router';
import {Location} from '@angular/common';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {LocaleService} from '@eg/core/locale.service';
import {PrintService} from '@eg/share/print/print.service';

@Component({
    selector: 'eg-staff-nav-bar',
    styleUrls: ['nav.component.css'],
    templateUrl: 'nav.component.html'
})

export class StaffNavComponent implements OnInit {

    // Locales that have Angular staff translations
    locales: any[];
    currentLocale: any;

    // When active, show a link to the experimental Angular staff catalog
    showAngularCatalog: boolean;

    constructor(
        private router: Router,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private locale: LocaleService,
        private printer: PrintService
    ) {
        this.locales = [];
    }

    ngOnInit() {

        this.locale.supportedLocales().subscribe(
            l => this.locales.push(l),
            err => {},
            () => {
                this.currentLocale = this.locales.filter(
                    l => l.code() === this.locale.currentLocaleCode())[0];
            }
        );

        // NOTE: this can eventually go away.
        // Avoid attempts to fetch org settings if the user has not yet
        // logged in (e.g. this is the login page).
        if (this.user()) {
            this.org.settings('ui.staff.angular_catalog.enabled')
            .then(settings => this.showAngularCatalog =
                Boolean(settings['ui.staff.angular_catalog.enabled']));
        }
    }

    user() {
        return this.auth.user() ? this.auth.user().usrname() : '';
    }

    workstation() {
        return this.auth.user() ? this.auth.workstation() : '';
    }

    setLocale(locale: any) {
        this.locale.setLocale(locale.code());
    }

    opChangeActive(): boolean {
        return this.auth.opChangeIsActive();
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
}


