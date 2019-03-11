import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {Pager} from '@eg/share/util/pager';
import {Params} from '@angular/router';

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

}

export class CatalogCnBrowseContext {
    value: string;
    // offset in pages from base browse term
    // e.g. -2 means 2 pages back (alphabetically) from the original search.
    offset: number;

    reset() {
        this.value = '';
        this.offset = 0;
    }

    isSearchable() {
        return this.value !== '';
    }
}

export class CatalogTermContext {
    fieldClass: string[];
    query: string[];
    joinOp: string[];
    matchOp: string[];
    format: string;
    available = false;
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

    termSearch: CatalogTermContext;
    marcSearch: CatalogMarcContext;
    identSearch: CatalogIdentContext;
    browseSearch: CatalogBrowseContext;
    cnBrowseSearch: CatalogCnBrowseContext;

    // Result from most recent search.
    result: CatalogSearchResults;
    searchState: CatalogSearchState = CatalogSearchState.PENDING;

    // List of IDs in page/offset context.
    resultIds: number[];

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
        this.searchState = CatalogSearchState.PENDING;
        this.termSearch.reset();
        this.marcSearch.reset();
        this.identSearch.reset();
        this.browseSearch.reset();
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
        const fieldClass = ts.fieldClass[idx];

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
        return query.replace(/[\^\$]/g, '');
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

        if (ts.hasBrowseEntry) {
            // stored as a comma-separated string of "entryId,fieldId"
            str += ` has_browse_entry(${ts.hasBrowseEntry})`;
        }

        if (ts.fromMetarecord) {
            str += ` from_metarecord(${ts.fromMetarecord})`;
        }

        if (ts.format) {
            str += ' format(' + ts.format + ')';
        }

        if (this.global) {
            str += ' depth(' +
                this.org.root().ou_type().depth() + ')';
        }

        if (ts.copyLocations[0] !== '') {
            str += ' locations(' + ts.copyLocations + ')';
        }

        str += ' site(' + this.searchOrg.shortname() + ')';

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
}

