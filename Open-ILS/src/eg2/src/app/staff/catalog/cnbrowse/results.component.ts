import {Component, OnInit, OnDestroy} from '@angular/core';
import {ActivatedRoute, Router, ParamMap} from '@angular/router';
import {Subscription} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService} from '@eg/share/catalog/bib-record.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';
import {BibRecordSummary} from '@eg/share/catalog/bib-record.service';

@Component({
  selector: 'eg-catalog-cn-browse-results',
  templateUrl: 'results.component.html'
})
export class CnBrowseResultsComponent implements OnInit, OnDestroy {

    searchContext: CatalogSearchContext;
    results: any[];
    routeSub: Subscription;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private cat: CatalogService,
        private bib: BibRecordService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
        this.routeSub = this.route.queryParamMap.subscribe(
            (params: ParamMap) => this.browseByUrl(params)
        );
    }

    ngOnDestroy() {
        this.routeSub.unsubscribe();
    }

    browseByUrl(params: ParamMap): void {
        this.catUrl.applyUrlParams(this.searchContext, params);
        const cbs = this.searchContext.cnBrowseSearch;

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
        this.bib.getBibSummary(
            bibIds.filter(distinct),
            this.searchContext.searchOrg.id(), depth
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
            },
            err => {},
            ()  => {
                this.bib.fleshBibUsers(bres);
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
        this.staffCat.cnBrowse();
    }

    nextPage() {
        this.searchContext.cnBrowseSearch.offset++;
        this.staffCat.cnBrowse();
    }

    /**
     * Propagate the search params along when navigating to each record.
     */
    navigateToRecord(summary: BibRecordSummary) {
        const params = this.catUrl.toUrlParams(this.searchContext);

        this.router.navigate(
            ['/staff/catalog/record/' + summary.id], {queryParams: params});
    }
}


