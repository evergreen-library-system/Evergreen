import {Component, OnInit, NgModule, ViewChild} from '@angular/core';
import {BehaviorSubject, Subscription} from 'rxjs';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, FacetFilter} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';
import {RecordBucketService} from '@eg/staff/cat/buckets/record/record-bucket.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {BasketService} from '@eg/share/catalog/basket.service';
import {EventService} from '@eg/core/event.service';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';

export const FACET_CONFIG = {
    display: [
        {facetClass : 'author',  facetOrder : ['personal', 'corporate']},
        {facetClass : 'subject', facetOrder : ['topic']},
        {facetClass : 'identifier', facetOrder : ['genre']},
        {facetClass : 'series',  facetOrder : ['seriestitle']},
        {facetClass : 'subject', facetOrder : ['name', 'geographic']}
    ]
};

@Component({
    selector: 'eg-catalog-result-facets',
    templateUrl: 'facets.component.html',
    styleUrls: ['./facets.component.css']
})
export class ResultFacetsComponent implements OnInit {

    favoriteBuckets$ = new BehaviorSubject<any[]>([]);
    recentBuckets$ = new BehaviorSubject<any[]>([]);

    searchContext: CatalogSearchContext;
    facetConfig: any;
    displayFullFacets: string[] = [];
    activeTab = 'facets';
    favoriteBucketIds: number[] = [];
    recentBucketIds: number[] = [];

    public isCollapsed = false;

    constructor(
        private evt: EventService,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
        private bucketService: RecordBucketService,
        private auth: AuthService,
        private org: OrgService,
        private toast: ToastService,
        private basket: BasketService,
    ) {
        this.facetConfig = FACET_CONFIG;
    }

    ngOnInit() {
        console.debug('ResultFacetsComponent, this', this);
        this.searchContext = this.staffCat.searchContext;
        this.bucketService.getBucketRefreshRequested().subscribe(() => {
            console.debug('refresh request sub triggered');
            this.loadBuckets();
        });
    }

    async onNavChange(event: NgbNavChangeEvent) {
        this.activeTab = event.nextId;
        // eslint-disable-next-line eqeqeq
        if (this.activeTab == 'buckets') {
            await this.loadBuckets();
        }
    }

    async loadBuckets() {
        await this.bucketService.loadFavoriteRecordBucketFlags(this.auth.user().id());
        this.favoriteBucketIds = this.bucketService.getFavoriteRecordBucketIds();
        this.recentBucketIds = this.bucketService.recentRecordBucketIds();
        const favoriteBuckets = await this.bucketService.retrieveRecordBuckets(this.favoriteBucketIds);
        this.favoriteBuckets$.next(favoriteBuckets);
        const recentBuckets = await this.bucketService.retrieveRecordBuckets(this.recentBucketIds);
        this.recentBuckets$.next(recentBuckets);
        await this.basket.getRecordIds(); // prime the service if nobody else has
    }

    addBasketToBucket(bucketId: number, clearBasket?: boolean) {
        this.basket.getRecordIds().then( basket_records => {
            this.bucketService.addBibsToRecordBucket(bucketId, basket_records)
                .then(resp => {
                    const evt = this.evt.parse(resp);
                    if (evt) {
                        console.error('addBasketToBucket failed:',evt);
                        this.toast.warning($localize`Could not add basket items to bucket :: {{evt.textcode}}`);
                    } else {
                        this.toast.success($localize`Basket items added to bucket`);
                        if (clearBasket) {this.basket.removeAllRecordIds();}
                        return this.loadBuckets();
                    }
                });
        });
    }

    getBasketCount() {
        return this.basket.recordCount();
    }

    orgName(orgId: number): string {
        return this.org.get(orgId)?.shortname();
    }

    facetIsApplied(cls: string, name: string, value: string): boolean {
        return this.searchContext.termSearch.hasFacet(new FacetFilter(cls, name, value));
    }

    getFacetUrlParams(cls: string, name: string, value: string): any {
        const context = this.staffCat.cloneContext(this.searchContext);
        context.termSearch.toggleFacet(new FacetFilter(cls, name, value));
        context.pager.offset = 0;
        return this.catUrl.toUrlParams(context);
    }

    // Build a list of the facet class+names that should be expanded to show all options.
    // More than one facet may be expanded
    facetToggle(name: string, fClass: string) {
        const index = this.displayFullFacets.indexOf(fClass+'-'+name);
        if ( index === -1 ) {  // not found
            this.displayFullFacets.push(fClass+'-'+name);
        } else { // delete it
            this.displayFullFacets.splice(index, 1);
        }
    }
}


