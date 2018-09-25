import {Component, OnInit, Input} from '@angular/core';
import {Observable} from 'rxjs/Observable';
import {map, switchMap, distinctUntilChanged} from 'rxjs/operators';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService} from '@eg/share/catalog/bib-record.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {PcrudService} from '@eg/core/pcrud.service';
import {StaffCatalogService} from '../catalog.service';
import {IdlObject} from '@eg/core/idl.service';

@Component({
  selector: 'eg-catalog-results',
  templateUrl: 'results.component.html'
})
export class ResultsComponent implements OnInit {

    searchContext: CatalogSearchContext;

    // Cache record creator/editor since this will likely be a
    // reasonably small set of data w/ lots of repitition.
    userCache: {[id: number]: IdlObject} = {};

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private cat: CatalogService,
        private bib: BibRecordService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;

        // Our search context is initialized on page load.  Once
        // ResultsComponent is active, it will not be reinitialized,
        // even if the route parameters changes (unless we change the
        // route reuse policy).  Watch for changes here to pick up new
        // searches.
        //
        // This will also fire on page load.
        this.route.queryParamMap.subscribe((params: ParamMap) => {

              // TODO: Angular docs suggest using switchMap(), but
              // it's not firing for some reason.  Also, could avoid
              // firing unnecessary searches when a param unrelated to
              // searching is changed by .map()'ing out only the desired
              // params and running through .distinctUntilChanged(), but
              // .map() is not firing either.  I'm missing something.
              this.searchByUrl(params);
        });
    }

    searchByUrl(params: ParamMap): void {
        this.catUrl.applyUrlParams(this.searchContext, params);

        if (this.searchContext.isSearchable()) {

            this.cat.search(this.searchContext)
            .then(ok => {
                this.cat.fetchFacets(this.searchContext);
                this.cat.fetchBibSummaries(this.searchContext)
                .then(ok2 => this.fleshSearchResults());
            });
        }
    }

    fleshSearchResults(): void {
        const records = this.searchContext.result.records;
        if (!records || records.length === 0) { return; }

        // Flesh the creator / editor fields with the user object.
        this.bib.fleshBibUsers(records.map(r => r.record));
    }

    searchIsDone(): boolean {
        return this.searchContext.searchState === CatalogSearchState.COMPLETE;
    }

}


