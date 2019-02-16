import {Component, OnInit, AfterViewInit, Renderer2} from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from './catalog.service';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-catalog-search-form',
  styleUrls: ['search-form.component.css'],
  templateUrl: 'search-form.component.html'
})
export class SearchFormComponent implements OnInit, AfterViewInit {

    context: CatalogSearchContext;
    ccvmMap: {[ccvm: string]: IdlObject[]} = {};
    cmfMap: {[cmf: string]: IdlObject} = {};
    showSearchFilters = false;
    copyLocations: IdlObject[];
    searchTab: string;

    constructor(
        private renderer: Renderer2,
        private router: Router,
        private org: OrgService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService
    ) {
        this.copyLocations = [];
    }

    ngOnInit() {
        this.ccvmMap = this.cat.ccvmMap;
        this.cmfMap = this.cat.cmfMap;
        this.context = this.staffCat.searchContext;

        // Start with advanced search options open
        // if any filters are active.
        this.showSearchFilters = this.filtersActive();
    }

    ngAfterViewInit() {
        // Query inputs are generated from search context data,
        // so they are not available until after the first render.
        // Search context data is extracted synchronously from the URL.

        // Avoid changing the tab in the lifecycle hook thread.
        setTimeout(() => {

            // Apply a tab if none was already specified
            if (!this.searchTab) {
                // Assumes that only one type of search will be searchable
                // at any given time.
                if (this.context.marcSearch.isSearchable()) {
                    this.searchTab = 'marc';
                } else if (this.context.identSearch.isSearchable()) {
                    this.searchTab = 'ident';
                } else if (this.context.browseSearch.isSearchable()) {
                    this.searchTab = 'browse';
                } else {
                    // Default tab
                    this.searchTab = 'term';
                    this.refreshCopyLocations();
                }
            }

            this.focusTabInput();
        });
    }

    onTabChange(evt: NgbTabChangeEvent) {
        this.searchTab = evt.nextId;

        // Focus after tab-change event has a chance to complete
        // or the tab body and its input won't exist yet and no
        // elements will be focus-able.
        setTimeout(() => this.focusTabInput());
    }

    focusTabInput() {
        // Select a DOM node to focus when the tab changes.
        let selector;
        switch (this.searchTab) {
            case 'ident':
                selector = '#ident-query-input';
                break;
            case 'marc':
                selector = '#first-marc-tag';
                break;
            case 'browse':
                selector = '#browse-term-input';
                break;
            default:
                this.refreshCopyLocations();
                selector = '#first-query-input';
        }

        try {
            // TODO: sometime the selector is not available in the DOM
            // until even later (even with setTimeouts).  Need to fix this.
            // Note the error is thrown from selectRootElement(), not the
            // call to .focus() on a null reference.
            this.renderer.selectRootElement(selector).focus();
        } catch (E) {}
    }

    /**
     * Display the advanced/extended search options when asked to
     * or if any advanced options are selected.
     */
    showFilters(): boolean {
        return this.showSearchFilters;
    }

    toggleFilters() {
        this.showSearchFilters = !this.showSearchFilters;
        this.refreshCopyLocations();
    }

    filtersActive(): boolean {

        if (this.context.termSearch.copyLocations[0] !== '') { return true; }

        // ccvm filters may be present without any filters applied.
        // e.g. if filters were applied then removed.
        let show = false;
        Object.keys(this.context.termSearch.ccvmFilters).forEach(ccvm => {
            if (this.context.termSearch.ccvmFilters[ccvm][0] !== '') {
                show = true;
            }
        });

        return show;
    }

    orgOnChange = (org: IdlObject): void => {
        this.context.searchOrg = org;
        this.refreshCopyLocations();
    }

    refreshCopyLocations() {
        if (!this.showFilters()) { return; }

        // TODO: is this how we avoid displaying too many locations?
        const org = this.context.searchOrg;
        if (org.id() === this.org.root().id()) {
            this.copyLocations = [];
            return;
        }

        this.cat.fetchCopyLocations(org).then(() =>
            this.copyLocations = this.cat.copyLocations
        );
    }

    orgName(orgId: number): string {
        return this.org.get(orgId).shortname();
    }

    addSearchRow(index: number): void {
        this.context.termSearch.query.splice(index, 0, '');
        this.context.termSearch.fieldClass.splice(index, 0, 'keyword');
        this.context.termSearch.joinOp.splice(index, 0, '&&');
        this.context.termSearch.matchOp.splice(index, 0, 'contains');
    }

    delSearchRow(index: number): void {
        this.context.termSearch.query.splice(index, 1);
        this.context.termSearch.fieldClass.splice(index, 1);
        this.context.termSearch.joinOp.splice(index, 1);
        this.context.termSearch.matchOp.splice(index, 1);
    }

    addMarcSearchRow(index: number): void {
        this.context.marcSearch.tags.splice(index, 0, '');
        this.context.marcSearch.subfields.splice(index, 0, '');
        this.context.marcSearch.values.splice(index, 0, '');
    }

    delMarcSearchRow(index: number): void {
        this.context.marcSearch.tags.splice(index, 1);
        this.context.marcSearch.subfields.splice(index, 1);
        this.context.marcSearch.values.splice(index, 1);
    }

    searchByForm(): void {
        this.context.pager.offset = 0; // New search

        // Form search overrides basket display
        this.context.showBasket = false;

        switch (this.searchTab) {

            case 'term': // AKA keyword search
                this.context.marcSearch.reset();
                this.context.browseSearch.reset();
                this.context.identSearch.reset();
                this.context.termSearch.hasBrowseEntry = '';
                this.context.termSearch.browseEntry = null;
                this.context.termSearch.fromMetarecord = null;
                this.context.termSearch.facetFilters = [];
                this.staffCat.search();
                break;

            case 'ident':
                this.context.marcSearch.reset();
                this.context.browseSearch.reset();
                this.context.termSearch.reset();
                this.staffCat.search();
                break;

            case 'marc':
                this.context.browseSearch.reset();
                this.context.termSearch.reset();
                this.context.identSearch.reset();
                this.staffCat.search();
                break;

            case 'browse':
                this.context.marcSearch.reset();
                this.context.termSearch.reset();
                this.context.identSearch.reset();
                this.context.browseSearch.pivot = null;
                this.staffCat.browse();
                break;
        }
    }

    // https://stackoverflow.com/questions/42322968/angular2-dynamic-input-field-lose-focus-when-input-changes
    trackByIdx(index: any, item: any) {
       return index;
    }

    searchIsActive(): boolean {
        return this.context.searchState === CatalogSearchState.SEARCHING;
    }

    goToBrowse() {
        this.router.navigate(['/staff/catalog/browse']);
    }
}


