import {Component, OnInit} from '@angular/core';
import {tap} from 'rxjs';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogSearchContext} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';

interface BrowsePage {
    leftPivot: number;
    rightPivot: number;
    entries: any[];
}

@Component({
    selector: 'eg-catalog-browse-pager',
    templateUrl: 'browse-pager.component.html'
})
export class BrowsePagerComponent implements OnInit {

    searchContext: CatalogSearchContext;
    browseLoading = false;
    prevEntry: any;
    nextEntry: any;

    constructor(
        private cat: CatalogService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
        this.fetchPageData().then(_ => this.setPrevNext());
    }

    pageEntryId(): number {
        return Number(
            this.searchContext.termSearch.hasBrowseEntry.split(',')[0]
        );
    }

    getEntryPageIndex(mbeId: number): number {
        let idx = null;
        this.staffCat.browsePagerData.forEach((page, index) => {
            page.entries.forEach(entry => {
                if (entry.browse_entry === mbeId) {
                    idx = index;
                }
            });
        });
        return idx;
    }


    getEntryPage(mbeId: number): BrowsePage {
        return this.staffCat.browsePagerData[this.getEntryPageIndex(mbeId)];
    }

    fetchPageData(): Promise<any> {

        if (this.getEntryPage(this.pageEntryId())) {
            // We have this page's data already
            return Promise.resolve();
        }

        return this.fetchBrowsePage(null);
    }

    // Grab a page of browse results
    fetchBrowsePage(prev: boolean): Promise<any> {
        const ctx = this.searchContext.clone();
        ctx.pager.limit = this.searchContext.pager.limit;
        ctx.termSearch.hasBrowseEntry = null; // avoid term search

        if (prev !== null) {
            // Fetching data for a prev/next page which is not the
            // current page.
            const page = this.getEntryPage(this.pageEntryId());
            const pivot = prev ? page.leftPivot : page.rightPivot;
            if (pivot === null) {
                console.debug('Browse has reached the end of the rainbow');
                return;
            }
            ctx.browseSearch.pivot = pivot;
        }

        const results = [];
        this.browseLoading = true;

        return this.cat.browse(ctx)
            .pipe(tap(result => results.push(result)))
            .toPromise().then(_ => {
                if (results.length === 0) { return; }

                // At the end of the data set, final pivots are not present
                let leftPivot = null;
                let rightPivot = null;
                if (results[0].pivot_point) {
                    leftPivot = results.shift().pivot_point;
                }
                if (results[results.length - 1].pivot_point) {
                    rightPivot = results.pop().pivot_point;
                }

                // We only care about entries with bib record sources
                let keepEntries = results.filter(e => Boolean(e.sources));

                if (leftPivot === null || rightPivot === null) {
                // When you reach the edge of the data set, you can get
                // the same browse entries from different API calls.
                // From what I can tell, the last page will always have
                // a half page of entries, even if you've already seen some
                // of them in the previous page.  Trim the dupes since they
                // affect the logic.
                    const keep = [];
                    keepEntries.forEach(e => {
                        if (!this.getEntryPage(e.browse_entry)) {
                            keep.push(e);
                        }
                    });
                    keepEntries = keep;
                }

                const page: BrowsePage = {
                    leftPivot: leftPivot,
                    rightPivot: rightPivot,
                    entries: keepEntries
                };

                if (prev) {
                    this.staffCat.browsePagerData.unshift(page);
                } else {
                    this.staffCat.browsePagerData.push(page);
                }
                this.browseLoading = false;
            });
    }

    // Collect enough browse data to display previous, current, and
    // next heading.  This can mean fetching an additional page of data.
    setPrevNext(take2 = false): Promise<any> {

        let previous: any;
        const mbeId = this.pageEntryId();

        this.staffCat.browsePagerData.forEach(page => {
            page.entries.forEach(entry => {

                if (previous) {
                    if (entry.browse_entry === mbeId) {
                        this.prevEntry = previous;
                    }
                    if (previous.browse_entry === mbeId) {
                        this.nextEntry = entry;
                    }
                }
                previous = entry;
            });
        });

        if (take2) {
            // If we have to call this more than twice it means we've
            // reached the boundary of the full data set and there's
            // no more data to fetch.
            return Promise.resolve();
        }

        let promise;

        if (!this.prevEntry) {
            promise = this.fetchBrowsePage(true);

        } else if (!this.nextEntry) {
            promise = this.fetchBrowsePage(false);
        }

        if (promise) {
            return promise.then(_ => this.setPrevNext(true));
        }

        return Promise.resolve();
    }

    setSearchPivot(prev?: boolean) {
        // When traversing browse result page boundaries, modify the
        // search pivot to keep up.

        const targetMbe = Number(
            prev ? this.prevEntry.browse_entry : this.nextEntry.browse_entry
        );

        const curPageIdx = this.getEntryPageIndex(this.pageEntryId());
        const targetPageIdx = this.getEntryPageIndex(targetMbe);

        if (targetPageIdx !== curPageIdx) {
            // We are crossing a page boundary

            const curPage = this.getEntryPage(this.pageEntryId());

            if (prev) {
                this.searchContext.browseSearch.pivot = curPage.leftPivot;

            } else {
                this.searchContext.browseSearch.pivot = curPage.rightPivot;
            }
        }
    }

    // Find the browse entry for the next/prev page and navigate there
    // if possible.  Returns false if not enough data is available.
    goToBrowsePage(prev: boolean): boolean {
        const ctx = this.searchContext;
        const target = prev ? this.prevEntry : this.nextEntry;

        if (!target) { return false; }

        this.setSearchPivot(prev);

        // Jump to the selected browse entry's page.
        ctx.termSearch.hasBrowseEntry = target.browse_entry + ',' + target.fields;
        ctx.pager.offset = 0; // this is a new records-for-browse-entry search
        this.staffCat.search();

        return true;
    }
}


