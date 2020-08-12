import {Component, OnInit, AfterViewInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronManagerService} from './patron.service';
import {PatronSearchComponent} from '@eg/staff/share/patron/search.component';

const MAIN_TABS =
    ['checkout', 'items_out', 'holds', 'bills', 'messages', 'edit', 'search'];

@Component({
  templateUrl: 'patron.component.html',
  styleUrls: ['patron.component.css']
})
export class PatronComponent implements OnInit, AfterViewInit {

    patronId: number;
    patronTab = 'search';
    altTab: string;
    showSummary = true;
    loading = true;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private store: ServerStoreService,
        public patronService: PatronService,
        public context: PatronManagerService
    ) {}

    ngOnInit() {
        this.watchForTabChange();
        this.load();
    }

    load() {
        this.loading = true;
        this.fetchSettings()
        .then(_ => this.loading = false);
    }

    fetchSettings(): Promise<any> {

        return this.store.getItemBatch([
            'eg.circ.patron.summary.collapse'
        ]).then(prefs => {
            this.showSummary = !prefs['eg.circ.patron.summary.collapse'];
        });
    }

    watchForTabChange() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.patronTab = params.get('tab') || 'search';
            this.patronId = +params.get('id');

            if (MAIN_TABS.includes(this.patronTab)) {
                this.altTab = null;
            } else {
                this.altTab = this.patronTab;
                this.patronTab = 'other';
            }

            const prevId =
                this.context.patron ? this.context.patron.id() : null;

            if (this.patronId) {
                if (this.patronId !== prevId) { // different patron
                    this.context.loadPatron(this.patronId);
                }
            } else {
                // Use the ID of the previously loaded patron.
                this.patronId = prevId;
            }
        });
    }

    ngAfterViewInit() {
    }

    beforeTabChange(evt: NgbNavChangeEvent) {
        // tab will change with route navigation.
        evt.preventDefault();

        this.patronTab = evt.nextId;
        this.routeToTab();
    }

    routeToTab() {
        let url = '/staff/circ/patron/';

        switch (this.patronTab) {
            case 'search':
            case 'bcsearch':
                url += this.patronTab;
                break;
            case 'other':
                url += `${this.patronId}/${this.altTab}`;
                break;
            default:
                url += `${this.patronId}/${this.patronTab}`;
        }

        this.router.navigate([url]);
    }

    showSummaryPane(): boolean {
        return this.showSummary || this.patronTab === 'search';
    }

    toggleSummaryPane() {
        this.store.setItem( // collapse is the opposite of show
            'eg.circ.patron.summary.collapse', this.showSummary);
        this.showSummary = !this.showSummary;
    }

    // Patron row single-clicked in the grid.  Load the patron without
    // leaving the search tab.
    patronSelectionChange(ids: number[]) {
        if (ids.length !== 1) { return; }

        const id = ids[0];
        if (id !== this.patronId) {
            this.patronId = id;
            this.context.loadPatron(id);
            return;
        }
    }

    // Route to checkout tab for selected patron.
    patronsActivated(rows: any[]) {
        if (rows.length !== 1) { return; }

        const id = rows[0].id();
        this.patronId = id;
        this.patronTab = 'checkout';
        this.routeToTab();
    }

    disablePurge(): boolean {
        return
            this.context.patron.super_user() === 't' ||
            this.patronId === this.auth.user().id();
    }

    purgeAccount() {
        // show scary warning, etc.

    }
}

