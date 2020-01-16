import {Component, OnInit, Input} from '@angular/core';
import {Router} from '@angular/router';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {StaffCatalogService} from '../catalog.service';
import {Pager} from '@eg/share/util/pager';


@Component({
  selector: 'eg-catalog-record-pagination',
  templateUrl: 'pagination.component.html'
})
export class RecordPaginationComponent implements OnInit {

    id: number;
    index: number;
    initDone = false;
    searchContext: CatalogSearchContext;

    _recordTab: string;
    @Input() set recordTab(tab: string) {
        this._recordTab = tab;
    }
    get recordTab(): string {
        return this._recordTab;
    }

    @Input() set recordId(id: number) {
        this.id = id;
        // Only apply new record data after the initial load
        if (this.initDone) {
            this.setIndex();
        }
    }

    constructor(
        private router: Router,
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService,
    ) {}

    ngOnInit() {
        this.initDone = true;
        this.setIndex();
    }

    routeToRecord(id: number) {
        let url = '/staff/catalog/record/' + id;
        if (this.recordTab) { url += '/' + this.recordTab; }
        const params = this.catUrl.toUrlParams(this.searchContext);
        this.router.navigate([url], {queryParams: params});
    }

    firstRecord(): void {
        this.findRecordAtIndex(0)
        .then(id => this.routeToRecord(id));
    }

    lastRecord(): void {
        this.findRecordAtIndex(this.searchContext.result.count - 1)
        .then(id => this.routeToRecord(id));
    }

    nextRecord(): void {
        this.findRecordAtIndex(this.index + 1)
        .then(id => this.routeToRecord(id));
    }

    prevRecord(): void {
        this.findRecordAtIndex(this.index - 1)
        .then(id => this.routeToRecord(id));
    }

    // Returns the offset of the record within the search results as a whole.
    searchIndex(idx: number): number {
        return idx + this.searchContext.pager.offset;
    }

    // Find the position of the current record in the search results
    // If no results are present or the record is not found, expand
    // the search scope to find the record.
    setIndex(): Promise<void> {
        this.searchContext = this.staffCat.searchContext;
        this.index = null;

        return new Promise((resolve, reject) => {

            this.index = this.searchContext.indexForResult(this.id);
            if (this.index !== null) {
                return resolve();
            }

            return this.refreshSearch().then(ok => {
                this.index = this.searchContext.indexForResult(this.id);
                resolve();
            });
        });
    }

    // Find the record ID at the specified search index.
    // If no data exists for the requested index, expand the search
    // to include data for that index.
    findRecordAtIndex(index: number): Promise<number> {

        // First see if the selected record sits in the current page
        // of search results.
        return new Promise((resolve, reject) => {
            const id = this.searchContext.resultIdAt(index);
            if (id) { return resolve(id); }

            console.debug(
                'Record paginator unable to find record at index ' + index);

            // If we have to re-run the search to find the record,
            // expand the search limit out just enough to find the
            // requested record plus one more.
            return this.refreshSearch(index + 2).then(
                ok => {
                    const rid = this.searchContext.resultIdAt(index);
                    if (rid) {
                        resolve(rid);
                    } else {
                        reject('no record found');
                    }
                }
            );
        });
    }

    refreshSearch(limit?: number): Promise<any> {

        console.debug('paginator refreshing search');

        if (!this.searchContext.isSearchable()) {
            return Promise.resolve();
        }

        const ctx = this.searchContext;

        const origPager = ctx.pager;
        const tmpPager = new Pager();
        tmpPager.limit = limit || 1000;

        ctx.pager = tmpPager;

        // Avoid fetching highlight data for a potentially large
        // list of record IDs
        ctx.getHighlightsFor = this.id;

        return this.cat.search(ctx)
        .then(_ => {
            ctx.pager = origPager;
            ctx.getHighlightsFor = null;
        });
    }

    returnToSearch(): void {
        // Fire the main search.  This will direct us back to /results/
        this.staffCat.search();
    }

}


