import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {StaffCatalogService} from '../catalog.service';
import {BibSummaryComponent} from '@eg/staff/share/bib-summary/bib-summary.component';
import {StoreService} from '@eg/core/store.service';

@Component({
  selector: 'eg-catalog-record',
  templateUrl: 'record.component.html'
})
export class RecordComponent implements OnInit {

    recordId: number;
    recordTab: string;
    summary: BibRecordSummary;
    searchContext: CatalogSearchContext;
    @ViewChild('recordTabs', { static: true }) recordTabs: NgbTabset;
    defaultTab: string; // eg.cat.default_record_tab

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private bib: BibRecordService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService,
        private store: StoreService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;

        this.defaultTab =
            this.store.getLocalItem('eg.cat.default_record_tab')
            || 'catalog';

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

            if (!this.recordTab) {
                this.recordTab = this.defaultTab || 'catalog';
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
    onTabChange(evt: NgbTabChangeEvent) {
        this.recordTab = evt.nextId;

        // prevent tab changing until after route navigation
        evt.preventDefault();

        this.routeToTab();
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
            return;
        }

        this.summary = null;
        this.bib.getBibSummary(
            this.recordId,
            this.searchContext.searchOrg.id(),
            this.searchContext.searchOrg.ou_type().depth()).toPromise()
        .then(summary => {
            this.summary =
                this.staffCat.currentDetailRecordSummary = summary;
            this.bib.fleshBibUsers([summary.record]);
        });
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
}


