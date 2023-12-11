import {Component, ViewChild, OnInit, HostListener} from '@angular/core';
import {Router, ActivatedRoute, ParamMap, RoutesRecognized} from '@angular/router';
import {Location} from '@angular/common';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Observable, throwError, empty} from 'rxjs';
import {filter, pairwise, concatMap, tap} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService, BillGridEntry} from './patron.service';
import {PatronSearch, PatronSearchComponent
} from '@eg/staff/share/patron/search.component';
import {EditToolbarComponent} from './edit-toolbar.component';
import {EditComponent} from './edit.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';

const MAIN_TABS =
    ['checkout', 'items_out', 'holds', 'bills', 'messages', 'edit', 'search'];

@Component({
    templateUrl: 'patron.component.html',
    styleUrls: ['patron.component.css']
})
export class PatronComponent implements OnInit {

    patronId: number;
    patronTab = 'search';
    altTab: string;
    statementXact: number;
    billingHistoryTab: string;
    showSummary = true;
    loading = true;
    showRecentPatrons = false;

    /* eg-patron-edit is unable to find #editorToolbar directly
     * within the template.  Adding a ref here allows it to
     * successfully transfer to the editor */
    @ViewChild('editorToolbar') private editorToolbar: EditToolbarComponent;

    @ViewChild('patronEditor') private patronEditor: EditComponent;

    @ViewChild('pendingChangesDialog')
    private pendingChangesDialog: ConfirmDialogComponent;

    @ViewChild('purgeConfirm1') private purgeConfirm1: ConfirmDialogComponent;
    @ViewChild('purgeConfirm2') private purgeConfirm2: ConfirmDialogComponent;
    @ViewChild('purgeConfirmOverride') private purgeConfirmOverride: ConfirmDialogComponent;
    @ViewChild('purgeStaffDialog') private purgeStaffDialog: PromptDialogComponent;
    @ViewChild('purgeBadBarcode') private purgeBadBarcode: AlertDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private ngLocation: Location,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private evt: EventService,
        private store: StoreService,
        private serverStore: ServerStoreService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
        this.watchForTabChange();
        this.load();
    }

    @HostListener('window:beforeunload', ['$event'])
    canDeactivate($event?: Event): Promise<boolean> {

        if (this.patronEditor && this.patronEditor.changesPending) {

            // Each warning dialog clears the current "changes are pending"
            // flag so the user is not presented with the dialog again
            // unless new changes are made.
            this.patronEditor.changesPending = false;

            if ($event) { // window.onbeforeunload
                $event.preventDefault();
                $event.returnValue = true;

            } else { // tab OR route change.
                return this.pendingChangesDialog.open().toPromise();
            }

        } else {
            return Promise.resolve(true);
        }
    }

    load() {
        this.loading = true;
        this.fetchSettings()
            .then(_ => this.loading = false);
    }

    fetchSettings(): Promise<any> {

        return this.serverStore.getItemBatch([
            'eg.circ.patron.summary.collapse'
        ]).then(prefs => {
            this.showSummary = !prefs['eg.circ.patron.summary.collapse'];
        });
    }

    recentPatronIds(): number[] {
        if (this.patronTab === 'search' && this.showRecentPatrons) {
            return this.store.getLoginSessionItem('eg.circ.recent_patrons') || [];
        } else {
            return null;
        }
    }

    watchForTabChange() {

        // When routing to a patron UI from a non-patron UI, clear all
        // patron info that may have persisted via the context service.
        this.router.events
            .pipe(filter((evt: any) => evt instanceof RoutesRecognized), pairwise())
            .subscribe((events: RoutesRecognized[]) => {
                const prevUrl = events[0].urlAfterRedirects || '';
                if (!prevUrl.startsWith('/staff/circ/patron')) {
                    this.context.reset();
                }
            });

        this.route.data.subscribe(data => {
            this.showRecentPatrons = (data && data.showRecentPatrons);
        });

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.patronTab = params.get('tab') || 'search';
            this.patronId = +params.get('id');
            this.statementXact = +params.get('xactId');
            this.billingHistoryTab = params.get('billingHistoryTab');

            if (MAIN_TABS.includes(this.patronTab)) {
                this.altTab = null;
            } else {
                this.altTab = this.patronTab;
                this.patronTab = 'other';
            }

            // Clear all previous patron data when returning to the
            // search from after other patron-level navigation.
            if (this.patronTab === 'search') {
                this.context.summary = null;
                this.patronId = null;
            }

            const prevId =
                this.context.summary ? this.context.summary.id : null;

            if (this.patronId) {

                if (this.patronId !== prevId) { // different patron
                    this.changePatron(this.patronId)
                        .then(_ => this.routeToAlertsPane());

                } else {
                    // Patron already loaded, most likely from the search tab.
                    // See if we still need to show alerts.
                    this.routeToAlertsPane();
                }
            } else {
                // Use the ID of the previously loaded patron.
                this.patronId = prevId;
            }
        });
    }

    // Navigate, opening new tabs when requested via control-click.
    // NOTE: The nav items have routerLinks, but for some reason,
    // control-click on the links does not open them in a new tab.
    // Mouse middle-click does, though.  *shrug*
    navItemClick(tab: string, evt: PointerEvent) {
        evt.preventDefault();
        this.canDeactivate().then(ok => {
            if (ok) {
                this.routeToTab(tab, evt.ctrlKey);
            }
        });
    }

    beforeTabChange(evt: NgbNavChangeEvent) {
        // Prevent the nav component from changing tabs so we can
        // control the behaviour.
        evt.preventDefault();
    }

    routeToTab(tab?: string, newWindow?: boolean) {
        let url = '/staff/circ/patron/';

        tab = tab || this.patronTab;

        switch (tab) {
            case 'search':
            case 'bcsearch':
                url += tab;
                break;
            case 'other':
                url += `${this.patronId}/${this.altTab}`;
                break;
            default:
                url += `${this.patronId}/${tab}`;
        }

        if (newWindow) {
            url = this.ngLocation.prepareExternalUrl(url);
            window.open(url);
        } else {
            this.router.navigate([url]);
        }
    }

    showSummaryPane(): boolean {
        return this.showSummary || this.patronTab === 'search';
    }

    toggleSummaryPane() {
        this.serverStore.setItem( // collapse is the opposite of show
            'eg.circ.patron.summary.collapse', this.showSummary);
        this.showSummary = !this.showSummary;
    }

    // Patron row single-clicked in the grid.  Load the patron without
    // leaving the search tab.
    patronSelectionChange(ids: number[]) {
        if (ids.length !== 1) { return; }

        const id = ids[0];
        if (id !== this.patronId) {
            this.changePatron(id);
        }
    }

    changePatron(id: number): Promise<any>  {
        this.patronId = id;
        return this.context.loadPatron(id);
    }

    routeToAlertsPane() {
        if (this.patronTab !== 'search' &&
            this.context.summary &&
            this.context.summary.alerts.hasAlerts() &&
            !this.context.patronAlertsShown()) {

            this.router.navigate(['/staff/circ/patron', this.patronId, 'alerts']);
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

    patronSearchFired(patronSearch: PatronSearch) {
        this.context.lastPatronSearch = patronSearch;
    }

    disablePurge(): boolean {
        return (
            !this.context.summary ||
            this.context.summary.patron.super_user() === 't' ||
            this.patronId === this.auth.user().id()
        );
    }

    purgeAccount() {

        this.purgeConfirm1.open().toPromise()
            .then(confirmed => {
                if (confirmed) {
                    return this.purgeConfirm2.open().toPromise();
                }
            })
            .then(confirmed => {
                if (confirmed) {
                    return this.net.request(
                        'open-ils.actor',
                        'open-ils.actor.user.has_work_perm_at',
                        this.auth.token(), 'STAFF_LOGIN', this.patronId
                    ).toPromise();
                }
            })
            .then(permOrgs => {
                if (permOrgs) {
                    if (permOrgs.length === 0) { // non-staff
                        return this.doThePurge();
                    } else {
                        return this.handleStaffPurge();
                    }
                }
            });
    }

    handleStaffPurge(): Promise<any> {

        return this.purgeStaffDialog.open().toPromise()
            .then(barcode => {
                if (barcode) {
                    return this.pcrud.search('ac', {barcode: barcode}).toPromise();
                }
            })
            .then(card => {
                if (card) {
                    return this.doThePurge(card.usr());
                } else {
                    return this.purgeBadBarcode.open();
                }
            });
    }

    doThePurge(destUserId?: number, override?: boolean): Promise<any> {
        let method = 'open-ils.actor.user.delete';
        if (override) { method += '.override'; }

        return this.net.request('open-ils.actor', method,
            this.auth.token(), this.patronId, destUserId).toPromise()
            .then(resp => {

                const evt = this.evt.parse(resp);
                if (evt) {
                    if (evt.textcode === 'ACTOR_USER_DELETE_OPEN_XACTS') {
                        return this.purgeConfirmOverride.open().toPromise()
                            .then(confirmed => {
                                if (confirmed) {
                                    return this.doThePurge(destUserId, true);
                                }
                            });
                    } else {
                        alert(evt);
                    }
                } else {
                    this.context.summary = null;
                    this.router.navigate(['/staff/circ/patron/search']);
                }
            });
    }

    counts(part: string, field: string): number {
        if (this.context.summary && this.context.summary.stats) {
            return this.context.summary.stats[part][field];
        } else {
            return 0;
        }
    }

    patronSearchCleared() {
        this.context.summary = null;
        this.patronId = null;
    }

    patronTitle(prefix: string = "Patron", suffix?: string) {
        if (!this.context.summary) return;

        const name = this.patronService.namePart(this.context.summary.patron, 'family_name') + ', ' + 
            this.patronService.namePart(this.context.summary.patron, 'first_given_name') + ' ' + 
            this.patronService.namePart(this.context.summary.patron, 'second_given_name');
    
        if (suffix)
            return [prefix, name, suffix].join(": ");
        else
            return [prefix, name].join(": ");
    }
}

