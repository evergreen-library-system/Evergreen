import {Component, OnInit, OnDestroy, ViewChild, Input} from '@angular/core';
import {Observable, Subscription} from 'rxjs';
import {tap, map, switchMap, distinctUntilChanged} from 'rxjs/operators';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {BibRecordService} from '@eg/share/catalog/bib-record.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {PcrudService} from '@eg/core/pcrud.service';
import {StaffCatalogService} from '../catalog.service';
import {IdlObject} from '@eg/core/idl.service';
import {BasketService} from '@eg/share/catalog/basket.service';
import {ServerStoreService} from '@eg/core/server-store.service';

@Component({
    selector: 'eg-catalog-results',
    templateUrl: 'results.component.html',
    styleUrls: ['results.component.css']
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
    showMoreDetails = false;

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private cat: CatalogService,
        private bib: BibRecordService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private serverStore: ServerStoreService,
        private basket: BasketService,
        private router: Router
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
        this.staffCat.browsePagerData = [];

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
            ctx => {
                this.jumpIfNecessary();
                this.applyRecordSelection();
            }
        );

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

    // For non-metarecord searches, jump to record page if only a
    // single hit is returned and the jump is enabled by library setting.
    // Unlike the OPAC version of jump-on-single-hit, the staff version
    // does not attempt to jump to the bib if it is the single member
    // of a sole metarecord returned by a metarecord search.
    jumpIfNecessary() {
        const ids = this.searchContext.currentResultIds();
        if (
            this.staffCat.jumpOnSingleHit &&
            ids.length === 1 &&
            !this.searchContext.termSearch.isMetarecordSearch()
        ) {
            this.router.navigate(['/staff/catalog/record/' + ids[0]], {queryParamsHandling: 'merge'});
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

            this.serverStore.getItem('eg.staff.catalog.results.show_more')
                .then(showMore => {

                    this.showMoreDetails =
                    this.searchContext.showResultExtras = showMore;

                    if (this.staffCat.prefOrg) {
                        this.searchContext.prefOu = this.staffCat.prefOrg.id();
                    }

                    this.cat.search(this.searchContext)
                        .then(ok => {
                            this.cat.fetchFacets(this.searchContext);
                            this.cat.fetchBibSummaries(this.searchContext);
                        });
                });
        }
    }

    toggleShowMore() {
        this.showMoreDetails = !this.showMoreDetails;

        this.serverStore.setItem(
            'eg.staff.catalog.results.show_more', this.showMoreDetails)
            .then(_ => {

                this.searchContext.showResultExtras = this.showMoreDetails;

                if (this.showMoreDetails) {
                    this.staffCat.search();
                } else {
                // Clear the collected copies.  No need for another search.
                    this.searchContext.result.records.forEach(rec => rec.copies = undefined);
                }
            });
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


