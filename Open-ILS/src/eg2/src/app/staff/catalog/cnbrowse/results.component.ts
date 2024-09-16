/* eslint-disable no-magic-numbers */
import {Component, Input, OnInit, OnDestroy} from '@angular/core';
import {ActivatedRoute, Router, ParamMap} from '@angular/router';
import {Subscription} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';
import {OrgService} from '@eg/core/org.service';

@Component({
    selector: 'eg-catalog-cn-browse-results',
    templateUrl: 'results.component.html',
    styleUrls: ['results.component.css']
})
export class CnBrowseResultsComponent implements OnInit, OnDestroy {

    // If set, this is a bib-focused browse
    @Input() bibSummary: BibRecordSummary;

    @Input() rowCount = 5;
    rowIndexList: number[] = [];

    // hard-coded because it requires template changes.
    colCount = 3;

    searchContext: CatalogSearchContext;
    results: any[] = [];
    routeSub: Subscription;

    // When browsing by a specific record, keep tabs on the initial
    // browse call number.
    browseCn: string;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private org: OrgService,
        private pcrud: PcrudService,
        private cat: CatalogService,
        private bib: BibRecordService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;

        if (this.bibSummary) {
            // Avoid clobbering the active search when browsing in
            // the context of a specific record.
            this.searchContext =
                this.staffCat.cloneContext(this.searchContext);
        }

        for (let idx = 0; idx < this.rowCount; idx++) {
            this.rowIndexList.push(idx);
        }

        let promise = Promise.resolve();
        if (this.bibSummary) {
            promise = this.getBrowseCallnumber();
        }

        promise.then(_ => {
            this.routeSub = this.route.queryParamMap.subscribe(
                (params: ParamMap) => this.browseByUrl(params)
            );
        });
    }

    ngOnDestroy() {
        this.routeSub.unsubscribe();
    }

    getBrowseCallnumber(): Promise<any> {
        let org = this.searchContext.searchOrg.id();

        if (this.searchContext.searchOrg.ou_type().can_have_vols() === 'f') {
            // If the current search org unit cannot hold volumes, search
            // across child org units.
            org = this.org.descendants(this.searchContext.searchOrg, true);
        }

        return this.pcrud.search('acn',
            {record: this.bibSummary.id, owning_lib: org, deleted: 'f'},
            {limit: 1}
        ).toPromise().then(cn =>
            this.browseCn = cn ? cn.label() : this.bibSummary.bibCallNumber
        );
    }

    browseByUrl(params: ParamMap): void {
        this.catUrl.applyUrlParams(this.searchContext, params);
        this.getBrowseResults();
    }

    getBrowseResults() {
        const cbs = this.searchContext.cnBrowseSearch;
        cbs.limit = this.rowCount * this.colCount;

        if (this.browseCn) {
            // Override any call number browse URL parameters
            cbs.value = this.browseCn;
        }

        if (cbs.isSearchable()) {
            this.results = [];
            this.cat.cnBrowse(this.searchContext)
                .subscribe(results => this.processResults(results));
        }
    }

    processResults(results: any[]) {
        this.results = results;

        const depth = this.searchContext.global ?
            this.searchContext.org.root().ou_type().depth() :
            this.searchContext.searchOrg.ou_type().depth();

        const bibIds = this.results.map(r => r.record().id());
        const distinct = (value: any, index: number, self: Array<number>) => {
            return self.indexOf(value) === index;
        };

        const bres: IdlObject[] = [];
        this.bib.getBibSummaries(
            bibIds.filter(distinct),
            this.searchContext.searchOrg.id(), this.searchContext.isStaff
        ).subscribe(
            summary => {
                // Response order not guaranteed.  Match the summary
                // object up with its response object.  A bib may be
                // linked to multiple call numbers
                const bibResults = this.results.filter(
                    r => Number(r.record().id()) === summary.id);

                bres.push(summary.record);

                // Use _ since result is an 'acn' object.
                bibResults.forEach(r => r._bibSummary = summary);
            }
        );
    }

    browseIsDone(): boolean {
        return this.searchContext.searchState === CatalogSearchState.COMPLETE;
    }

    browseIsActive(): boolean {
        return this.searchContext.searchState === CatalogSearchState.SEARCHING;
    }

    browseHasResults(): boolean {
        return this.browseIsDone() && this.results.length > 0;
    }

    prevPage() {
        this.searchContext.cnBrowseSearch.offset--;
        if (this.bibSummary) {
            // Browse without navigation
            this.getBrowseResults();
        } else {
            this.staffCat.cnBrowse();
        }

    }

    nextPage() {
        this.searchContext.cnBrowseSearch.offset++;
        if (this.bibSummary) {
            // Browse without navigation
            this.getBrowseResults();
        } else {
            this.staffCat.cnBrowse();
        }
    }

    /**
     * Propagate the search params along when navigating to each record.
     */
    navigateToRecord(summary: BibRecordSummary) {
        const params = this.catUrl.toUrlParams(this.searchContext);

        this.router.navigate(
            ['/staff/catalog/record/' + summary.id], {queryParams: params});
    }

    resultSlice(rowIdx: number): number[] {
        const offset = rowIdx * this.colCount;
        return this.results.slice(offset, offset + this.colCount);
    }

    isCenter(rowIdx: number, colIdx: number): boolean {
        const total = this.rowCount * this.colCount;
        return Math.floor(total / 2) === ((rowIdx * this.colCount) + colIdx);
    }

    orgName(orgId: number): string {
        return this.org.get(orgId)?.shortname();
    }

    getAuthorSearchParams(summary: BibRecordSummary): any {
        return this.staffCat.getAuthorSearchParams(summary);
    }
}


