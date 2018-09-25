import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {Pager} from '@eg/share/util/pager';
import {Params} from '@angular/router';

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

// Not an angular service.
// It's conceviable there could be multiple contexts.
export class CatalogSearchContext {

    // Search options and filters
    available = false;
    global = false;
    sort: string;
    fieldClass: string[];
    query: string[];
    identQuery: string;
    identQueryType: string; // isbn, issn, etc.
    joinOp: string[];
    matchOp: string[];
    format: string;
    searchOrg: IdlObject;
    ccvmFilters: {[ccvmCode: string]: string[]};
    facetFilters: FacetFilter[];
    isStaff: boolean;

    // Result from most recent search.
    result: any = {};
    searchState: CatalogSearchState = CatalogSearchState.PENDING;

    // List of IDs in page/offset context.
    resultIds: number[] = [];

    // Utility stuff
    pager: Pager;
    org: OrgService;

    constructor() {
        this.pager = new Pager();
        this.reset();
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
        this.resultIds[resultIdx + this.pager.offset] = id;
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

    /**
     * Return search context to its default state, resetting search
     * parameters and clearing any cached result data.
     * This does not reset global filters like limit-to-available
     * search-global, or search-org.
     */
    reset(): void {
        this.pager.offset = 0;
        this.format = '';
        this.sort = '';
        this.query = [''];
        this.identQuery = null;
        this.identQueryType = 'identifier|isbn';
        this.fieldClass  = ['keyword'];
        this.matchOp = ['contains'];
        this.joinOp = [''];
        this.ccvmFilters = {};
        this.facetFilters = [];
        this.result = {};
        this.resultIds = [];
        this.searchState = CatalogSearchState.PENDING;
    }

    isSearchable(): boolean {

        if (this.identQuery && this.identQueryType) {
            return true;
        }

        return this.query.length
            && this.query[0] !== ''
            && this.searchOrg !== null;
    }

    compileSearch(): string {
        let str = '';

        if (this.available) {
            str += '#available';
        }

        if (this.sort) {
            // e.g. title, title.descending
            const parts = this.sort.split(/\./);
            if (parts[1]) { str += ' #descending'; }
            str += ' sort(' + parts[0] + ')';
        }

        if (this.identQuery && this.identQueryType) {
            if (str) { str += ' '; }
            str += this.identQueryType + ':' + this.identQuery;

        } else {

            // -------
            // Compile boolean sub-query components
            if (str.length) { str += ' '; }
            const qcount = this.query.length;

            // if we multiple boolean query components, wrap them in parens.
            if (qcount > 1) { str += '('; }
            this.query.forEach((q, idx) => {
                str += this.compileBoolQuerySet(idx);
            });
            if (qcount > 1) { str += ')'; }
            // -------
        }

        if (this.format) {
            str += ' format(' + this.format + ')';
        }

        if (this.global) {
            str += ' depth(' +
                this.org.root().ou_type().depth() + ')';
        }

        str += ' site(' + this.searchOrg.shortname() + ')';

        Object.keys(this.ccvmFilters).forEach(field => {
            if (this.ccvmFilters[field][0] !== '') {
                str += ' ' + field + '(' + this.ccvmFilters[field] + ')';
            }
        });

        this.facetFilters.forEach(f => {
            str += ' ' + f.facetClass + '|'
                + f.facetName + '[' + f.facetValue + ']';
        });

        return str;
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

    compileBoolQuerySet(idx: number): string {
        let query = this.query[idx];
        const joinOp = this.joinOp[idx];
        const matchOp = this.matchOp[idx];
        const fieldClass = this.fieldClass[idx];

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


