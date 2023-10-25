import {Component, OnInit, Input} from '@angular/core';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, FacetFilter} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';

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

    searchContext: CatalogSearchContext;
    facetConfig: any;
    displayFullFacets: string[] = [];

    constructor(
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService
    ) {
        this.facetConfig = FACET_CONFIG;
    }

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
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
        let index = this.displayFullFacets.indexOf(fClass+'-'+name);
        if ( index == -1 ) {  // not found
            this.displayFullFacets.push(fClass+'-'+name);
        }
        else { // delete it
            this.displayFullFacets.splice(index, 1);
        }
    }
}


