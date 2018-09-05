import {Component, OnInit, AfterViewInit, Renderer2} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from './catalog.service';

@Component({
  selector: 'eg-catalog-search-form',
  styleUrls: ['search-form.component.css'],
  templateUrl: 'search-form.component.html'
})
export class SearchFormComponent implements OnInit, AfterViewInit {

    searchContext: CatalogSearchContext;
    ccvmMap: {[ccvm: string]: IdlObject[]} = {};
    cmfMap: {[cmf: string]: IdlObject} = {};
    showAdvancedSearch = false;

    constructor(
        private renderer: Renderer2,
        private org: OrgService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        this.ccvmMap = this.cat.ccvmMap;
        this.cmfMap = this.cat.cmfMap;
        this.searchContext = this.staffCat.searchContext;

        // Start with advanced search options open
        // if any filters are active.
        this.showAdvancedSearch = this.hasAdvancedOptions();

    }

    ngAfterViewInit() {
        // Query inputs are generated from search context data,
        // so they are not available until after the first render.
        // Search context data is extracted synchronously from the URL.

        if (this.searchContext.identQuery) {
            // Focus identifier query input if identQuery is in progress
            this.renderer.selectRootElement('#ident-query-input').focus();
        } else {
            // Otherwise focus the main query input
            this.renderer.selectRootElement('#first-query-input').focus();
        }
    }

    /**
     * Display the advanced/extended search options when asked to
     * or if any advanced options are selected.
     */
    showAdvanced(): boolean {
        return this.showAdvancedSearch;
    }

    hasAdvancedOptions(): boolean {
        // ccvm filters may be present without any filters applied.
        // e.g. if filters were applied then removed.
        let show = false;
        Object.keys(this.searchContext.ccvmFilters).forEach(ccvm => {
            if (this.searchContext.ccvmFilters[ccvm][0] !== '') {
                show = true;
            }
        });

        if (this.searchContext.identQuery) {
            show = true;
        }

        return show;
    }

    orgOnChange = (org: IdlObject): void => {
        this.searchContext.searchOrg = org;
    }

    addSearchRow(index: number): void {
        this.searchContext.query.splice(index, 0, '');
        this.searchContext.fieldClass.splice(index, 0, 'keyword');
        this.searchContext.joinOp.splice(index, 0, '&&');
        this.searchContext.matchOp.splice(index, 0, 'contains');
    }

    delSearchRow(index: number): void {
        this.searchContext.query.splice(index, 1);
        this.searchContext.fieldClass.splice(index, 1);
        this.searchContext.joinOp.splice(index, 1);
        this.searchContext.matchOp.splice(index, 1);
    }

    formEnter(source) {
        this.searchContext.pager.offset = 0;

        switch (source) {

            case 'query': // main search form query input

                // Be sure a previous ident search does not take precedence
                // over the newly entered/submitted search query
                this.searchContext.identQuery = null;
                break;

            case 'ident': // identifier query input
                const iq = this.searchContext.identQuery;
                const qt = this.searchContext.identQueryType;
                if (iq) {
                    // Ident queries ignore search-specific filters.
                    this.searchContext.reset();
                    this.searchContext.identQuery = iq;
                    this.searchContext.identQueryType = qt;
                }
                break;
        }

        this.searchByForm();
    }

    // https://stackoverflow.com/questions/42322968/angular2-dynamic-input-field-lose-focus-when-input-changes
    trackByIdx(index: any, item: any) {
       return index;
    }

    searchByForm(): void {
        this.staffCat.search();
    }

    searchIsActive(): boolean {
        return this.searchContext.searchState === CatalogSearchState.SEARCHING;
    }

}


