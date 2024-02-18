import {Component, OnInit, ViewChild, HostListener} from '@angular/core';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {StaffCatalogService} from '../catalog.service';
import {AddedContentComponent} from '@eg/staff/catalog/content/added-content.component';
import {StoreService} from '@eg/core/store.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {MarcEditorComponent} from '@eg/staff/share/marc-edit/editor.component';
import {HoldingsMaintenanceComponent} from './holdings.component';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import { ServerStoreService } from '@eg/core/server-store.service';

@Component({
    selector: 'eg-catalog-record',
    templateUrl: 'record.component.html',
    styleUrls: ['record.component.css']
})
export class RecordComponent implements OnInit {

    recordId: number;
    recordTab: string;
    added_content_activated = false;
    added_content_sources: string[] = [];
    summary: BibRecordSummary;
    searchContext: CatalogSearchContext;
    @ViewChild('recordTabs', { static: true }) recordTabs: NgbNav;
    @ViewChild('marcEditor', {static: false}) marcEditor: MarcEditorComponent;
    @ViewChild('addedContent', { static: true }) addedContent: AddedContentComponent;

    @ViewChild('holdingsMaint', {static: false})
        holdingsMaint: HoldingsMaintenanceComponent;

    defaultTab: string; // eg.cat.default_record_tab

    @ViewChild('pendingChangesDialog', {static: false})
        pendingChangesDialog: ConfirmDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private auth: AuthService,
        private bib: BibRecordService,
        private staffCat: StaffCatalogService,
        private holdings: HoldingsService,
        private store: StoreService,
        private serverStore: ServerStoreService,
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;

        this.defaultTab =
            this.store.getLocalItem('eg.cat.default_record_tab')
            || 'item_table';

        // Watch for URL record ID changes
        // This includes the initial route.
        // When applying the default configured tab, no navigation occurs
        // to apply the tab name to the URL, it displays as the default.
        // This is done so no intermediate redirect is required, which
        // messes with browser back/forward navigation.
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.recordTab = params.get('tab');
            this.recordId = +params.get('id');
            this.searchContext = this.staffCat.searchContext;

            this.store.setLocalItem('eg.cat.last_record_retrieved', this.recordId);

            if (!this.recordTab) {
                this.recordTab = this.defaultTab || 'item_table';
            }

            this.loadRecord();
        });
    }

    setDefaultTab() {
        this.defaultTab = this.recordTab;
        this.store.setLocalItem('eg.cat.default_record_tab', this.recordTab);
    }

    // Changing a tab in the UI means changing the route.
    // Changing the route ultimately results in changing the tab.
    beforeNavChange(evt: NgbNavChangeEvent) {

        // prevent tab changing until after route navigation
        evt.preventDefault();

        // Protect against tab changes with dirty data.
        this.canDeactivate().then(ok => {
            if (ok) {
                this.recordTab = evt.nextId;
                this.routeToTab();
            }
        });
    }

    /*
     * Handle 3 types of navigation which can cause loss of data.
     * 1. Record detail tab navigation (see also beforeTabChange())
     * 2. Intra-Angular route navigation away from the record detail page
     * 3. Browser page unload/reload
     *
     * For the #1, and #2, display a eg confirmation dialog.
     * For #3 use the stock browser onbeforeunload dialog.
     *
     * Note in this case a tab change is a route change, but it's one
     * which does not cause RecordComponent to unload, so it has to be
     * manually tracked in beforeTabChange().
     */
    @HostListener('window:beforeunload', ['$event'])
    canDeactivate($event?: Event): Promise<boolean> {

        if (this.marcEditor && this.marcEditor.changesPending()) {

            // Each warning dialog clears the current "changes are pending"
            // flag so the user is not presented with the dialog again
            // unless new changes are made.
            this.marcEditor.clearPendingChanges();

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

    routeToTab() {
        const url =
            `/staff/catalog/record/${this.recordId}/${this.recordTab}`;

        // Retain search parameters
        this.router.navigate([url], {queryParamsHandling: 'merge'});
    }

    loadRecord(): void {

        // Avoid re-fetching the same record summary during tab navigation.
        if (this.staffCat.currentDetailRecordSummary &&
            this.recordId === this.staffCat.currentDetailRecordSummary.id) {
            this.summary = this.staffCat.currentDetailRecordSummary;
            this.activateAddedContent();
            return;
        }

        this.summary = null;
        this.bib.getBibSummary(
            this.recordId,
            this.searchContext.searchOrg.id(),
            this.searchContext.isStaff).toPromise()
            .then(summary => {
                this.summary =
                this.staffCat.currentDetailRecordSummary = summary;
                this.activateAddedContent();
            });
    }

    // Lets us intercept the summary object and augment it with
    // search highlight data if/when it becomes available from
    // an externally executed search.
    summaryForDisplay(): BibRecordSummary {
        if (!this.summary) { return null; }
        const sum = this.summary;
        const ctx = this.searchContext;

        if (Object.keys(sum.displayHighlights).length === 0) {
            if (ctx.highlightData[sum.id]) {
                sum.displayHighlights = ctx.highlightData[sum.id];
            }
        }

        return this.summary;
    }

    currentSearchOrg(): IdlObject {
        if (this.staffCat && this.staffCat.searchContext) {
            return this.staffCat.searchContext.searchOrg;
        }
        return null;
    }

    handleMarcRecordSaved() {
        this.staffCat.currentDetailRecordSummary = null;
        this.loadRecord();
    }

    // Our actions component broadcast a request to add holdings.
    // If our Holdings Maintenance component is active/visible, ask
    // it to figure out what data to pass to the holdings editor.
    // Otherwise, just tell it to create a new call number and
    // copy at the current working location.
    addHoldingsRequested() {
        if (this.holdingsMaint && this.holdingsMaint.holdingsGrid) {
            this.holdingsMaint.openHoldingAdd(
                this.holdingsMaint.holdingsGrid.context.getSelectedRows(),
                true, true
            );

        } else {

            this.holdings.spawnAddHoldingsUi(
                this.recordId, null, [{owner: this.auth.user().ws_ou()}]);
        }
    }

    // This just sets the record component-level flag. choices about /if/ to
    // gather AC should go in here and set this.added_content_activated as needed.
    activateAddedContent(): void {
        // NovelistSelect settings
        this.serverStore.getItemBatch([
            'staff.added_content.novelistselect.profile',
            'staff.added_content.novelistselect.passwd'
        ]).then(settings => {
            // eslint-disable-next-line eqeqeq
            const activate = !!(Object.values(settings).filter(v => !!v).length == 2);
            this.added_content_activated ||= activate;

            if (activate) {
                if (!this.added_content_sources.includes('novelist')) {
                    this.added_content_sources.push('novelist');
                }
            }
        });
    }
}


