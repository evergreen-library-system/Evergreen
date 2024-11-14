/* eslint-disable */
import {Component, OnInit, AfterViewInit, Renderer2} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogSearchContext, CatalogSearchState} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from './catalog.service';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';

// Maps opac-style default tab names to local tab names.
const LEGACY_TAB_NAME_MAP = {
    expert: 'marc',
    numeric: 'ident',
    advanced: 'term'
};

// Automatically collapse the search form on these pages
const COLLAPSE_ON_PAGES = [
    new RegExp(/staff\/catalog\/record\//),
    new RegExp(/staff\/catalog\/hold\//)
];

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
    activeFiltersCount: number = 0;
    libraryGroups: IdlObject[];
    copyLocations: IdlObject[];
    copyLocationGroups: IdlObject[];
    searchTab: string;
    combineLibraryAndLocationGroups: boolean;

    refreshingLibraryGroups: boolean = false;
    refreshingCopyLocationGroups: boolean = false;

    // What does the user want us to do?
    // On pages where we can be hidded, start out hidden, unless the
    // user has opted to show us.
    showSearchFormSetting = false;

    // Show the course search limit checkbox only if opted in to the
    // course module
    showCourseFilter = false;


    constructor(
        private renderer: Renderer2,
        private router: Router,
        private route: ActivatedRoute,
        private org: OrgService,
        private cat: CatalogService,
        private store: ServerStoreService,
        private staffCat: StaffCatalogService
    ) {
        this.copyLocations = [];
        this.copyLocationGroups = [];
        this.libraryGroups = [];

    }

    ngOnInit() {
        this.ccvmMap = this.cat.ccvmMap;
        this.cmfMap = this.cat.cmfMap;
        this.context = this.staffCat.searchContext;
        this.combineLibraryAndLocationGroups = this.cat.combineLibraryAndLocationGroups

        // Start with advanced search options open
        // if any filters are active.
        this.activeFiltersCount = this.filtersActive();
        this.showSearchFilters = this.activeFiltersCount > 0;

        // Some search scenarios, like rendering a search template,
        // will not be searchable and thus not resovle to a specific
        // search tab.  Check to see if a specific tab is requested
        // via the URL.
        this.route.queryParams.subscribe(params => {
            if (params.searchTab) {
                this.searchTab = params.searchTab;
            }
        });

        this.store.getItem('eg.catalog.search.form.open')
            .then(value => this.showSearchFormSetting = value);

        this.store.getItem('eg.staffcat.course_materials_selector')
            .then(value => this.showCourseFilter = value);
    }

    // Are we on a page where the form is allowed to be collapsed.
    canBeHidden(): boolean {
        for (let idx = 0; idx < COLLAPSE_ON_PAGES.length; idx++) {
            const pageRegex = COLLAPSE_ON_PAGES[idx];
            if (this.router.url.match(pageRegex)) {
                return true;
            }
        }
        return false;
    }

    hideForm(): boolean {
        return this.canBeHidden() && !this.showSearchFormSetting;
    }

    toggleFormDisplay() {
        this.showSearchFormSetting = !this.showSearchFormSetting;
        this.store.setItem('eg.catalog.search.form.open', this.showSearchFormSetting);
    }

    ngAfterViewInit() {
        // Query inputs are generated from search context data,
        // so they are not available until after the first render.
        // Search context data is extracted synchronously from the URL.

        // Avoid changing the tab in the lifecycle hook thread.
        setTimeout(() => {

            if (this.context.identSearch.queryType === '') {
                this.context.identSearch.queryType = 'identifier|isbn';
            }

            // Apply a tab if none was already specified
            if (!this.searchTab) {
                // Assumes that only one type of search will be searchable
                // at any given time.
                if (this.context.marcSearch.isSearchable()) {
                    this.searchTab = 'marc';
                } else if (this.context.identSearch.isSearchable()) {
                    this.searchTab = 'ident';

                // Browse search may remain 'searchable' even though we
                // are displaying bibs linked to a browse entry.
                // This is so browse search paging can be added to
                // the record list page.
                } else if (this.context.browseSearch.isSearchable()
                    && !this.context.termSearch.hasBrowseEntry) {
                    this.searchTab = 'browse';
                } else if (this.context.termSearch.isSearchable()) {
                    this.searchTab = 'term';

                } else {

                    this.searchTab =
                        LEGACY_TAB_NAME_MAP[this.staffCat.defaultTab]
                        || this.staffCat.defaultTab || 'term';

                }

                this.refreshLibraryGroups();
                this.refreshCopyLocationGroups();
                if (this.searchTab === 'term') {
                    this.refreshCopyLocations();
                }
            }

            this.focusTabInput();
        });
    }

    lassoAndLocationGroupsAllowed() {
        return this.searchTab === 'term';
    }

    onNavChange(evt: NgbNavChangeEvent) {
        this.searchTab = evt.nextId;

        // Focus after tab-change event has a chance to complete
        // or the tab body and its input won't exist yet and no
        // elements will be focus-able.
        setTimeout(() => this.focusTabInput());
    }

    focusTabInput() {
        // Select a DOM node to focus when the tab changes.
        let selector: string;
        switch (this.searchTab) {
            case 'ident':
                this.refreshLibraryGroups();
                this.refreshCopyLocationGroups();
                selector = '#ident-query-input';
                break;
            case 'marc':
                selector = '#first-marc-tag';
                break;
            case 'browse':
                selector = '#browse-term-input';
                break;
            case 'cnbrowse':
                selector = '#cnbrowse-term-input';
                break;
            default:
                this.refreshLibraryGroups();
                this.refreshCopyLocationGroups();
                this.refreshCopyLocations();
                selector = '#first-query-input';
        }

        try {
            // TODO: sometime the selector is not available in the DOM
            // until even later (even with setTimeouts).  Need to fix this.
            // Note the error is thrown from selectRootElement(), not the
            // call to .focus() on a null reference.
            this.renderer.selectRootElement(selector).focus();
        } catch (E) { /* empty */ }
    }

    /**
     * Display the advanced/extended search options when asked to
     * or if any advanced options are selected.
     */
    showFilters(): boolean {
        // Note that filters may become active due to external
        // actions on the search context.  Always show the filters
        // if filter values are applied.
        return this.showSearchFilters;
    }

    toggleFilters() {
        this.showSearchFilters = !this.showSearchFilters;
        this.refreshCopyLocations();
    }

    updateFilters(filterName: string, selectElement: any): void {
        const selectedValues = Array.from(selectElement.options)
            .filter((option: HTMLOptionElement) => option.selected)
            .map((option: HTMLOptionElement) => option.value);

        this.context.termSearch.ccvmFilters[filterName] = selectedValues.length  && selectedValues[0] !== '' ? selectedValues : [''];
        this.filtersActive();
    }

    filtersActive(): number {
        this.activeFiltersCount = 0;
        if (this.context.termSearch.copyLocations[0] !== '') { 
            this.activeFiltersCount++;
        }

        if (this.context.termSearch.date1) {
            this.activeFiltersCount++;
        }

        // ccvm filters may be present without any filters applied.
        // e.g. if filters were applied then removed.
        Object.keys(this.context.termSearch.ccvmFilters).forEach(ccvm => {
            if (this.context.termSearch.ccvmFilters[ccvm][0] !== '') {
                this.activeFiltersCount++;
            }
        });

        return this.activeFiltersCount;
    }

    orgOnChange = (org: IdlObject): void => {
        this.context.searchOrg = org;
        this.refreshCopyLocations();
        this.refreshCopyLocationGroups();
        this.refreshLibraryGroups();
    }

    refreshCopyLocations() {
        if (!this.showFilters()) { return; }

        this.cat.fetchCopyLocations(this.context.searchOrg).then(() =>
            this.copyLocations = this.cat.copyLocations
        );
    }

    refreshCopyLocationGroups() {
        if (this.refreshingCopyLocationGroups) return;
        this.refreshingCopyLocationGroups = true;
        this.cat.fetchCopyLocationGroups(this.context.searchOrg).then(() => {
            this.copyLocationGroups = this.cat.copyLocationGroups
            this.refreshingCopyLocationGroups = false;
        });
    }

    refreshLibraryGroups() {
        if (this.refreshingLibraryGroups) return;
        this.refreshingLibraryGroups = true;
        this.cat.fetchLibraryGroups(this.context.searchOrg).then(() => {
            this.libraryGroups = this.cat.libraryGroups
            this.refreshingLibraryGroups = false;
        });
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
        this.activeFiltersCount = this.filtersActive();

        // Form search overrides basket display
        this.context.showBasket = false;

        this.context.scrub(this.searchTab);

        switch (this.searchTab) {

            case 'term':
            case 'ident':
            case 'marc':
                this.staffCat.search();
                break;

            case 'browse':
                this.staffCat.browse();
                break;

            case 'cnbrowse':
                this.staffCat.cnBrowse();
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

    // It's possible to chose invalid combos depending on the order of selection
    preventBogusCombos(idx: number) {
        if (this.context.termSearch.fieldClass[idx] === 'keyword') {
            const op = this.context.termSearch.matchOp[idx];
            if (op === 'exact' || op === 'starts') {
                this.context.termSearch.matchOp[idx] = 'contains';
            }
        }
    }

    showBookplate(): boolean {
        return this.staffCat.enableBookplates;
    }
    showExcludeElectronic(): boolean {
        return this.staffCat.showExcludeElectronic;
    }
    searchFilters(): string[] {
        return this.staffCat.searchFilters;
    }

    reserveComboboxChange(limiterStatus: string): void {
        switch (limiterStatus) {
            case 'any':
                this.context.termSearch.onReserveFilter = false;
                break;
            case 'limit':
                this.context.termSearch.onReserveFilter = true;
                this.context.termSearch.onReserveFilterNegated = false;
                break;
            case 'negated':
                this.context.termSearch.onReserveFilter = true;
                this.context.termSearch.onReserveFilterNegated = true;
        }
    }
}


