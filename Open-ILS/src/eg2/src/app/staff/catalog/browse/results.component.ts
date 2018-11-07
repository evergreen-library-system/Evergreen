import {Component, OnInit, Input} from '@angular/core';
import {Observable} from 'rxjs/Observable';
import {Subscription} from 'rxjs/Subscription';
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
  selector: 'eg-catalog-browse-results',
  templateUrl: 'results.component.html'
})
export class BrowseResultsComponent implements OnInit {

    searchContext: CatalogSearchContext;
    results: any[];

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
        this.route.queryParamMap.subscribe((params: ParamMap) => {
            this.browseByUrl(params);
        });
    }

    browseByUrl(params: ParamMap): void {
        this.catUrl.applyUrlParams(this.searchContext, params);
        const bs = this.searchContext.browseSearch;

        // SearchContext applies a default fieldClass value of 'keyword'.
        // Replace with 'title', since there is no 'keyword' browse.
        if (bs.fieldClass === 'keyword') {
            bs.fieldClass = 'title';
        }

        if (bs.isSearchable()) {
            this.results = [];
            this.cat.browse(this.searchContext)
                .subscribe(result => this.addResult(result))
        }
    }

    addResult(result: any) {

        result.compiledHeadings = [];

        // Avoi dupe headings per see
        const seen: any = {};

        result.sees.forEach(sees => {
            if (!sees.control_set) { return; }

            sees.headings.forEach(headingStruct => {
                const fieldId = Object.keys(headingStruct)[0];
                const heading = headingStruct[fieldId][0];

                const inList = result.list_authorities.filter(
                    id => Number(id) === Number(heading.target))[0]

                if (   heading.target 
                    && heading.main_entry
                    && heading.target_count 
                    && !inList
                    && !seen[heading.target]) {

                    seen[heading.target] = true;

                    result.compiledHeadings.push({
                        heading: heading.heading,
                        target: heading.target,
                        target_count: heading.target_count,
                        type: heading.type
                    });
                }
            });
        });

        this.results.push(result);
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
        const firstResult = this.results[0];
        if (firstResult) {
            this.searchContext.browseSearch.pivot = firstResult.pivot_point;
            this.staffCat.browse();
        }
    }

    nextPage() {
        const lastResult = this.results[this.results.length - 1];
        if (lastResult) {
            this.searchContext.browseSearch.pivot = lastResult.pivot_point;
            this.staffCat.browse();
        }
    }

    searchByBrowseEntry(result) { 

        // Avoid propagating browse values to term search.
        this.searchContext.browseSearch.reset();

        this.searchContext.termSearch.hasBrowseEntry = 
            result.browse_entry + ',' + result.fields;
        this.staffCat.search();
    }

    // NOTE: to test unauthorized heading display in concerto
    // browse for author = kab
    newBrowseFromHeading(heading) {
        this.searchContext.browseSearch.value = heading.heading;
        this.staffCat.browse();
    }
}


