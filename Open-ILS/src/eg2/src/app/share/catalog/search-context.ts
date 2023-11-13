/* eslint-disable no-shadow */
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {Pager} from '@eg/share/util/pager';
import {ArrayUtil} from '@eg/share/util/array';

// CCVM's we care about in a catalog context
// Don't fetch them all because there are a lot.
export const CATALOG_CCVM_FILTERS = [
    'item_type',
    'item_form',
    'item_lang',
    'audience',
    'audience_group',
    'vr_format',
    'bib_level',
    'lit_form',
    'search_format',
    'icon_format'
];

export enum CatalogSearchState {
    PENDING,
    SEARCHING,
    COMPLETE
}

export class FacetFilter {
    facetClass: string;
    facetName: string;
    facetValue: string;

    constructor(cls: string, name: string, value: string) {
        this.facetClass = cls;
        this.facetName  = name;
        this.facetValue = value;
    }

    equals(filter: FacetFilter): boolean {
        return (
            this.facetClass === filter.facetClass &&
            this.facetName  === filter.facetName &&
            this.facetValue === filter.facetValue
        );
    }

    clone(): FacetFilter {
        return new FacetFilter(
            this.facetClass, this.facetName, this.facetValue);
    }
}

export class CatalogSearchResults {
    ids: number[];
    count: number;
    [misc: string]: any;

    constructor() {
        this.ids = [];
        this.count = 0;
    }
}

export class CatalogBrowseContext {
    value: string;
    pivot: number;
    fieldClass: string;

    reset() {
        this.value = '';
        this.pivot = null;
        this.fieldClass = 'title';
    }

    isSearchable(): boolean {
        return (
            this.value !== '' &&
            this.fieldClass !== ''
        );
    }

    clone(): CatalogBrowseContext {
        const ctx = new CatalogBrowseContext();
        ctx.value = this.value;
        ctx.pivot = this.pivot;
        ctx.fieldClass = this.fieldClass;
        return ctx;
    }

    equals(ctx: CatalogBrowseContext): boolean {
        return ctx.value === this.value && ctx.fieldClass === this.fieldClass;
    }
}

export class CatalogMarcContext {
    tags: string[];
    subfields: string[];
    values: string[];

    reset() {
        this.tags = [''];
        this.values = [''];
        this.subfields = [''];
    }

    isSearchable() {
        return (
            this.tags[0] !== '' &&
            this.values[0] !== ''
        );
    }

    clone(): CatalogMarcContext {
        const ctx = new CatalogMarcContext();
        ctx.tags = [].concat(this.tags);
        ctx.values = [].concat(this.values);
        ctx.subfields = [].concat(this.subfields);
        return ctx;
    }

    equals(ctx: CatalogMarcContext): boolean {
        return ArrayUtil.equals(ctx.tags, this.tags)
            && ArrayUtil.equals(ctx.values, this.values)
            && ArrayUtil.equals(ctx.subfields, this.subfields);
    }
}

export class CatalogIdentContext {
    value: string;
    queryType: string;

    reset() {
        this.value = '';
        this.queryType = '';
    }

    isSearchable() {
        return (
            this.value !== ''
            && this.queryType !== ''
        );
    }

    clone(): CatalogIdentContext {
        const ctx = new CatalogIdentContext();
        ctx.value = this.value;
        ctx.queryType = this.queryType;
        return ctx;
    }

    equals(ctx: CatalogIdentContext): boolean {
        return ctx.value === this.value && ctx.queryType === this.queryType;
    }
}

export class CatalogCnBrowseContext {
    value: string;
    // offset in pages from base browse term
    // e.g. -2 means 2 pages back (alphabetically) from the original search.
    offset: number;

    // Maintain a separate page size limit since it will generally
    // differ from other search page sizes.
    limit: number;

    reset() {
        this.value = '';
        this.offset = 0;
        this.limit = 5; // UI will modify
    }

    isSearchable() {
        return this.value !== '' && this.value !== undefined;
    }

    clone(): CatalogCnBrowseContext {
        const ctx = new CatalogCnBrowseContext();
        ctx.value = this.value;
        ctx.offset = this.offset;
        ctx.limit = this.limit;
        return ctx;
    }

    equals(ctx: CatalogCnBrowseContext): boolean {
        return ctx.value === this.value;
    }
}

export class CatalogTermContext {
    fieldClass: string[];
    query: string[];
    joinOp: string[];
    matchOp: string[];
    format: string;
    locationGroupOrLasso: string = '';
    lasso: string;
    available = false;
    onReserveFilter = false;
    onReserveFilterNegated = false;
    ccvmFilters: {[ccvmCode: string]: string[]};
    facetFilters: FacetFilter[];
    copyLocations: string[]; // ID's, but treated as strings in the UI.

    // True when searching for metarecords
    groupByMetarecord: boolean;

    // Filter results by records which link to this metarecord ID.
    fromMetarecord: number;

    hasBrowseEntry: string; // "entryId,fieldId"
    browseEntry: IdlObject;
    date1: number;
    date2: number;
    dateOp: string; // before, after, between, is

    excludeElectronic = false;

    reset() {
        this.query = [''];
        this.fieldClass  = ['keyword'];
        this.matchOp = ['contains'];
        this.joinOp = [''];
        this.facetFilters = [];
        this.copyLocations = [''];
        this.format = '';
        this.hasBrowseEntry = '';
        this.date1 = null;
        this.date2 = null;
        this.dateOp = 'is';
        this.fromMetarecord = null;

        // Apply empty string values for each ccvm filter
        this.ccvmFilters = {};
        CATALOG_CCVM_FILTERS.forEach(code => this.ccvmFilters[code] = ['']);
    }

    clone(): CatalogTermContext {
        const ctx = new CatalogTermContext();

        ctx.query = [].concat(this.query);
        ctx.fieldClass = [].concat(this.fieldClass);
        ctx.matchOp = [].concat(this.matchOp);
        ctx.joinOp = [].concat(this.joinOp);
        ctx.copyLocations = [].concat(this.copyLocations);
        ctx.format = this.format;
        ctx.hasBrowseEntry = this.hasBrowseEntry;
        ctx.date1 = this.date1;
        ctx.date2 = this.date2;
        ctx.dateOp = this.dateOp;
        ctx.fromMetarecord = this.fromMetarecord;

        ctx.facetFilters = this.facetFilters.map(f => f.clone());

        ctx.ccvmFilters = {};
        Object.keys(this.ccvmFilters).forEach(
            key => ctx.ccvmFilters[key] = this.ccvmFilters[key]);

        return ctx;
    }

    equals(ctx: CatalogTermContext): boolean {
        if (   ArrayUtil.equals(ctx.query, this.query)
            && ArrayUtil.equals(ctx.fieldClass, this.fieldClass)
            && ArrayUtil.equals(ctx.matchOp, this.matchOp)
            && ArrayUtil.equals(ctx.joinOp, this.joinOp)
            && ArrayUtil.equals(ctx.copyLocations, this.copyLocations)
            && ctx.format === this.format
            && ctx.hasBrowseEntry === this.hasBrowseEntry
            && ctx.date1 === this.date1
            && ctx.date2 === this.date2
            && ctx.dateOp === this.dateOp
            && ctx.fromMetarecord === this.fromMetarecord
            && ArrayUtil.equals(
                ctx.facetFilters, this.facetFilters, (a, b) => a.equals(b))
            && Object.keys(this.ccvmFilters).length ===
                Object.keys(ctx.ccvmFilters).length
        ) {

            // So far so good, compare ccvm hash contents
            let mismatch = false;
            Object.keys(this.ccvmFilters).forEach(key => {
                if (!ArrayUtil.equals(this.ccvmFilters[key], ctx.ccvmFilters[key])) {
                    mismatch = true;
                }
            });

            return !mismatch;
        }

        return false;
    }


    // True when grouping by metarecord but not when displaying the
    // contents of a metarecord.
    isMetarecordSearch(): boolean {
        return (
            this.isSearchable() &&
            this.groupByMetarecord &&
            this.fromMetarecord === null
        );
    }

    isSearchable(): boolean {
        return (
            this.query[0] !== ''
            || this.hasBrowseEntry !== ''
            || this.fromMetarecord !== null
        );
    }

    hasFacet(facet: FacetFilter): boolean {
        return Boolean(
            this.facetFilters.filter(f => f.equals(facet))[0]
        );
    }

    removeFacet(facet: FacetFilter): void {
        this.facetFilters = this.facetFilters.filter(f => !f.equals(facet));
    }

    addFacet(facet: FacetFilter): void {
        if (!this.hasFacet(facet)) {
            this.facetFilters.push(facet);
        }
    }

    toggleFacet(facet: FacetFilter): void {
        if (this.hasFacet(facet)) {
            this.removeFacet(facet);
        } else {
            this.facetFilters.push(facet);
        }
    }
}



// Not an angular service.
// It's conceviable there could be multiple contexts.
export class CatalogSearchContext {

    // Attributes that are used across different contexts.
    sort: string;
    isStaff: boolean;
    showBasket: boolean;
    searchOrg: IdlObject;
    global: boolean;
    prefOu: number;

    termSearch: CatalogTermContext;
    marcSearch: CatalogMarcContext;
    identSearch: CatalogIdentContext;
    browseSearch: CatalogBrowseContext;
    cnBrowseSearch: CatalogCnBrowseContext;

    // Result from most recent search.
    result: CatalogSearchResults;
    searchState: CatalogSearchState = CatalogSearchState.PENDING;

    // fetch and show extra holdings data, etc.
    showResultExtras = false;

    // List of IDs in page/offset context.
    resultIds: number[];

    // If a bib ID is provided, instruct the search code to
    // only fetch field highlight data for a single record instead
    // of all search results.
    getHighlightsFor: number;
    highlightData: {[id: number]: {[field: string]: string | string[]}} = {};

    // Utility stuff
    pager: Pager;
    org: OrgService;

    constructor() {
        this.pager = new Pager();
        this.termSearch = new CatalogTermContext();
        this.marcSearch = new CatalogMarcContext();
        this.identSearch = new CatalogIdentContext();
        this.browseSearch = new CatalogBrowseContext();
        this.cnBrowseSearch = new CatalogCnBrowseContext();
        this.reset();
    }

    // Performs a deep clone of the search context as-is.
    clone(): CatalogSearchContext {
        const ctx = new CatalogSearchContext();

        ctx.sort = this.sort;
        ctx.isStaff = this.isStaff;
        ctx.global = this.global;

        // OK to share since the org object won't be changing.
        ctx.searchOrg = this.searchOrg;

        ctx.termSearch = this.termSearch.clone();
        ctx.marcSearch = this.marcSearch.clone();
        ctx.identSearch = this.identSearch.clone();
        ctx.browseSearch = this.browseSearch.clone();
        ctx.cnBrowseSearch = this.cnBrowseSearch.clone();

        return ctx;
    }

    equals(ctx: CatalogSearchContext): boolean {
        return (
            this.termSearch.equals(ctx.termSearch)
            && this.marcSearch.equals(ctx.marcSearch)
            && this.identSearch.equals(ctx.identSearch)
            && this.browseSearch.equals(ctx.browseSearch)
            && this.cnBrowseSearch.equals(ctx.cnBrowseSearch)
            && this.sort === ctx.sort
            && this.global === ctx.global
        );
    }

    /**
     * Return search context to its default state, resetting search
     * parameters and clearing any cached result data.
     */
    reset(): void {
        this.pager.offset = 0;
        this.sort = '';
        this.showBasket = false;
        this.result = new CatalogSearchResults();
        this.resultIds = [];
        this.highlightData = {};
        this.searchState = CatalogSearchState.PENDING;
        this.termSearch.reset();
        this.marcSearch.reset();
        this.identSearch.reset();
        this.browseSearch.reset();
        this.cnBrowseSearch.reset();
    }

    isSearchable(): boolean {
        return (
            this.showBasket ||
            this.termSearch.isSearchable() ||
            this.marcSearch.isSearchable() ||
            this.identSearch.isSearchable() ||
            this.browseSearch.isSearchable()
        );
    }

    // List of result IDs for the current page of data.
    currentResultIds(): number[] {
        const ids = [];
        const max = Math.min(
            this.pager.offset + this.pager.limit,
            this.pager.resultCount
        );
        for (let idx = this.pager.offset; idx < max; idx++) {
            ids.push(this.resultIds[idx]);
        }
        return ids;
    }

    addResultId(id: number, resultIdx: number ): void {
        this.resultIds[resultIdx + this.pager.offset] = Number(id);
    }

    // Return the record at the requested index.
    resultIdAt(index: number): number {
        return this.resultIds[index] || null;
    }

    // Return the index of the requested record
    indexForResult(id: number): number {
        for (let i = 0; i < this.resultIds.length; i++) {
            if (this.resultIds[i] === id) {
                return i;
            }
        }
        return null;
    }

    compileMarcSearchArgs(): any {
        const searches: any = [];
        const ms = this.marcSearch;

        ms.values.forEach((val, idx) => {
            if (val !== '') {
                searches.push({
                    restrict: [{
                        // "_" is the wildcard subfield for the API.
                        subfield: ms.subfields[idx] ? ms.subfields[idx] : '_',
                        tag: ms.tags[idx]
                    }],
                    term: ms.values[idx]
                });
            }
        });

        const args: any = {
            searches: searches,
            limit : this.pager.limit,
            offset : this.pager.offset,
            org_unit: this.searchOrg.id()
        };

        if (this.global) {
            args.depth = this.org.root().ou_type().depth();
        }

        if (this.sort) {
            const parts = this.sort.split(/\./);
            args.sort = parts[0]; // title, author, etc.
            if (parts[1]) { args.sort_dir = 'descending'; }
        }

        return args;
    }

    compileIdentSearchQuery(): string {
        const str = ' site(' + this.searchOrg.shortname() + ')';
        return str + ' ' +
            this.identSearch.queryType + ':' + this.identSearch.value;
    }


    compileBoolQuerySet(idx: number): string {
        const ts = this.termSearch;
        let query = ts.query[idx];
        const joinOp = ts.joinOp[idx];
        const matchOp = ts.matchOp[idx];
        let fieldClass = ts.fieldClass[idx];

        // Bookplates are filters but may be displayed as regular
        // text search indexes.
        if (fieldClass === 'bookplate') { return ''; }

        if (fieldClass === 'jtitle') { fieldClass = 'title'; }

        let str = '';
        if (!query) { return str; }

        if (idx > 0) { str += ' ' + joinOp + ' '; }

        str += '(';
        if (fieldClass) { str += fieldClass + ':'; }

        switch (matchOp) {
            case 'phrase':
                query = this.addQuotes(this.stripQuotes(query));
                break;
            case 'nocontains':
                query = '-' + this.addQuotes(this.stripQuotes(query));
                break;
            case 'exact':
                query = '^' + this.stripAnchors(query) + '$';
                break;
            case 'starts':
                query = this.addQuotes('^' +
                    this.stripAnchors(this.stripQuotes(query)));
                break;
        }

        return str + query + ')';
    }

    stripQuotes(query: string): string {
        return query.replace(/"/g, '');
    }

    stripAnchors(query: string): string {
        return query.replace(/[\^$]/g, '');
    }

    addQuotes(query: string): string {
        if (query.match(/ /)) {
            return '"' + query + '"';
        }
        return query;
    }

    compileTermSearchQuery(): string {
        const ts = this.termSearch;
        let str = '';

        if (ts.available) {
            str += '#available';
        }

        if (ts.onReserveFilter) {
            str += ' ';
            if (ts.onReserveFilterNegated) {
                str += '-';
            }
            str += 'on_reserve(' + this.searchOrg.id() + ')';
        }

        if (ts.excludeElectronic) {
            str += '-search_format(electronic)';
        }

        if (this.sort) {
            // e.g. title, title.descending
            const parts = this.sort.split(/\./);
            if (parts[1]) { str += ' #descending'; }
            str += ' sort(' + parts[0] + ')';
        }

        if (ts.date1 && ts.dateOp) {
            switch (ts.dateOp) {
                case 'is':
                    str += ` date1(${ts.date1})`;
                    break;
                case 'before':
                    str += ` before(${ts.date1})`;
                    break;
                case 'after':
                    str += ` after(${ts.date1})`;
                    break;
                case 'between':
                    if (ts.date2) {
                        str += ` between(${ts.date1},${ts.date2})`;
                    }
            }
        }

        str = str.trimStart();

        // -------
        // Compile boolean sub-query components
        if (str.length) { str += ' '; }
        const qcount = ts.query.length;

        // if we multiple boolean query components, wrap them in parens.
        if (qcount > 1) { str += '('; }
        ts.query.forEach((q, idx) => {
            str += this.compileBoolQuerySet(idx);
        });
        if (qcount > 1) { str += ')'; }
        // -------

        // Append bookplate queries as filters
        ts.query.forEach((q, idx) => {
            const space = str.length > 0 ? ' ' : '';
            const query = ts.query[idx];
            const fieldClass = ts.fieldClass[idx];
            if (query && fieldClass === 'bookplate') {
                str += `${space}copy_tag(*,${query})`;
            }
        });

        // Journal Title queries means performing a title search
        // with a filter.  Filters are global, so append to the front
        // of the query.
        if (ts.fieldClass.filter(fc => fc === 'jtitle').length > 0) {
            str = 'bib_level(s) ' + str;
        }

        if (ts.hasBrowseEntry) {
            // stored as a comma-separated string of "entryId,fieldId"
            str += ` has_browse_entry(${ts.hasBrowseEntry})`;
        }

        if (ts.fromMetarecord) {
            str += ` from_metarecord(${ts.fromMetarecord})`;
        }

        if (ts.format) {
            str += ' search_format(' + ts.format + ')';
        }

        if (this.global) {
            str += ' depth(' +
                this.org.root().ou_type().depth() + ')';
        }

        if (ts.copyLocations[0] !== '') {
            str += ' locations(' + ts.copyLocations + ')';
        }

        if (ts.locationGroupOrLasso !== '') {
            str += ' ' + ts.locationGroupOrLasso;
        } else {
            str += ' site(' + this.searchOrg.shortname() + ')';
        }

        Object.keys(ts.ccvmFilters).forEach(field => {
            if (ts.ccvmFilters[field][0] !== '') {
                str += ' ' + field + '(' + ts.ccvmFilters[field] + ')';
            }
        });

        ts.facetFilters.forEach(f => {
            str += ' ' + f.facetClass + '|'
                + f.facetName + '[' + f.facetValue + ']';
        });

        return str;
    }

    // A search context can collect enough data for multiple search
    // types to be searchable (e.g. users navigate through parts of a
    // search form).  Calling this method and providing a search type
    // ensures the context is cleared of any data unrelated to the
    // desired type.
    scrub(searchType: string): void {

        switch (searchType) {

            case 'term': // AKA keyword search
                this.marcSearch.reset();
                this.browseSearch.reset();
                this.identSearch.reset();
                this.cnBrowseSearch.reset();
                this.termSearch.browseEntry = null;
                this.termSearch.fromMetarecord = null;
                this.termSearch.facetFilters = [];

                if (this.termSearch.query[0] !== '') {
                    // If the user has entered a query, it takes precedence
                    // over the source browse entry or source metarecord.
                    this.termSearch.hasBrowseEntry = null;
                    this.termSearch.fromMetarecord = null;
                }

                break;

            case 'ident':
                this.marcSearch.reset();
                this.browseSearch.reset();
                this.termSearch.reset();
                this.cnBrowseSearch.reset();
                break;

            case 'marc':
                this.browseSearch.reset();
                this.termSearch.reset();
                this.identSearch.reset();
                this.cnBrowseSearch.reset();
                break;

            case 'browse':
                this.marcSearch.reset();
                this.termSearch.reset();
                this.identSearch.reset();
                this.cnBrowseSearch.reset();
                this.browseSearch.pivot = null;
                break;

            case 'cnbrowse':
                this.marcSearch.reset();
                this.termSearch.reset();
                this.identSearch.reset();
                this.browseSearch.reset();
                this.cnBrowseSearch.offset = 0;
                break;
        }
    }
}

