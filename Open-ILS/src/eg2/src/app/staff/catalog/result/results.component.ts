import {Component, OnInit, OnDestroy, Input} from '@angular/core';
import {Observable, Subscription} from 'rxjs';
import {map, switchMap, distinctUntilChanged} from 'rxjs/operators';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService} from '@eg/share/catalog/bib-record.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {PcrudService} from '@eg/core/pcrud.service';
import {StaffCatalogService} from '../catalog.service';
import {IdlObject} from '@eg/core/idl.service';
import {BasketService} from '@eg/share/catalog/basket.service';

@Component({
  selector: 'eg-catalog-results',
  templateUrl: 'results.component.html'
})
export class ResultsComponent implements OnInit, OnDestroy {

    searchContext: CatalogSearchContext;

    // Cache record creator/editor since this will likely be a
    // reasonably small set of data w/ lots of repitition.
    userCache: {[id: number]: IdlObject} = {};

    allRecsSelected: boolean;

    searchSub: Subscription;
    routeSub: Subscription;
    basketSub: Subscription;

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private cat: CatalogService,
        private bib: BibRecordService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private basket: BasketService
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
        this.routeSub =
            this.route.queryParamMap.subscribe((params: ParamMap) => {

              // TODO: Angular docs suggest using switchMap(), but
              // it's not firing for some reason.  Also, could avoid
              // firing unnecessary searches when a param unrelated to
              // searching is changed by .map()'ing out only the desired
              // params and running through .distinctUntilChanged(), but
              // .map() is not firing either.  I'm missing something.
              this.searchByUrl(params);
        });

        // After each completed search, update the record selector.
        this.searchSub = this.cat.onSearchComplete.subscribe(
            ctx => this.applyRecordSelection());

        // Watch for basket changes applied by other components.
        this.basketSub = this.basket.onChange.subscribe(
            () => this.applyRecordSelection());
    }

    ngOnDestroy() {
        if (this.routeSub) {
            this.routeSub.unsubscribe();
            this.searchSub.unsubscribe();
            this.basketSub.unsubscribe();
        }
    }

    // Apply the select-all checkbox when all visible records
    // are selected.
    applyRecordSelection() {
        const ids = this.searchContext.currentResultIds();
        let allChecked = true;
        ids.forEach(id => {
            if (!this.basket.hasRecordId(id)) {
                allChecked = false;
            }
        });
        this.allRecsSelected = allChecked;
    }

    // Pull values from the URL and run the requested search.
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

    // Records file into place randomly as the server returns data.
    // To reduce page display shuffling, avoid showing the list of
    // records until the first few are ready to render.
    shouldStartRendering(): boolean {

        if (this.searchHasResults()) {
            const pageCount = this.searchContext.currentResultIds().length;
            switch (pageCount) {
                case 1:
                    return this.searchContext.result.records[0];
                default:
                    return this.searchContext.result.records[0]
                        && this.searchContext.result.records[1];
            }
        }

        return false;
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

    searchIsActive(): boolean {
        return this.searchContext.searchState === CatalogSearchState.SEARCHING;
    }

    searchHasResults(): boolean {
        return this.searchIsDone() && this.searchContext.result.count > 0;
    }

    toggleAllRecsSelected() {
        const ids = this.searchContext.currentResultIds();

        if (this.allRecsSelected) {
            this.basket.addRecordIds(ids);
        } else {
            this.basket.removeRecordIds(ids);
        }
    }
}


