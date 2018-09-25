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

@Component({
  selector: 'eg-catalog-record',
  templateUrl: 'record.component.html'
})
export class RecordComponent implements OnInit {

    recordId: number;
    recordTab: string;
    summary: BibRecordSummary;
    searchContext: CatalogSearchContext;
    @ViewChild('recordTabs') recordTabs: NgbTabset;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private bib: BibRecordService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;

        // Watch for URL record ID changes
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.recordTab = params.get('tab') || 'copy_table';
            this.recordId = +params.get('id');
            this.searchContext = this.staffCat.searchContext;
            this.loadRecord();
        });
    }

    // Changing a tab in the UI means changing the route.
    // Changing the route ultimately results in changing the tab.
    onTabChange(evt: NgbTabChangeEvent) {
        this.recordTab = evt.nextId;

        // prevent tab changing until after route navigation
        evt.preventDefault();

        let url = '/staff/catalog/record/' + this.recordId;
        if (this.recordTab !== 'copy_table') {
            url += '/' + this.recordTab;
        }

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
}


