import {Injectable} from '@angular/core';
import {ParamMap} from '@angular/router';
import {OrgService} from '@eg/core/org.service';
import {CatalogSearchContext, CatalogBrowseContext, CatalogMarcContext,
   CatalogTermContext, FacetFilter} from './search-context';
import {CATALOG_CCVM_FILTERS} from './search-context';

@Injectable()
export class CatalogUrlService {

    // consider supporting a param name prefix/namespace

    constructor(private org: OrgService) { }

    /**
     * Returns a URL query structure suitable for using with
     * router.navigate(..., {queryParams:...}).
     * No navigation is performed within.
     */
    toUrlParams(context: CatalogSearchContext):
            {[key: string]: string | string[]} {

        const params: any = {};

        if (context.searchOrg) {
            params.org = context.searchOrg.id();
        }

        if (context.pager.limit) {
            params.limit = context.pager.limit;
        }

        if (context.pager.offset) {
            params.offset = context.pager.offset;
        }

        // These fields can be copied directly into place
        ['limit', 'offset', 'sort', 'global', 'showBasket', 'sort']
        .forEach(field => {
            if (context[field]) {
                // Only propagate applied values to the URL.
                params[field] = context[field];
            }
        });

        if (context.marcSearch.isSearchable()) {
            const ms = context.marcSearch;
            params.marcTag = [];
            params.marcSubfield = [];
            params.marcValue = [];

            ms.values.forEach((val, idx) => {
                if (val !== '') {
                    params.marcTag.push(ms.tags[idx]);
                    params.marcSubfield.push(ms.subfields[idx]);
                    params.marcValue.push(ms.values[idx]);
                }
            });
        }

        if (context.identSearch.isSearchable()) {
            params.identQuery = context.identSearch.value;
            params.identQueryType = context.identSearch.queryType;
        }

        if (context.browseSearch.isSearchable()) {
            params.browseTerm = context.browseSearch.value;
            params.browseClass = context.browseSearch.fieldClass;
            if (context.browseSearch.pivot) {
                params.browsePivot = context.browseSearch.pivot;
            }
        }

        if (context.termSearch.isSearchable()) {

            const ts = context.termSearch;

            params.query = [];
            params.fieldClass = [];
            params.joinOp = [];
            params.matchOp = [];

            ['format', 'available', 'hasBrowseEntry', 'date1',
                'date2', 'dateOp', 'groupByMetarecord', 'fromMetarecord']
            .forEach(field => {
                if (ts[field]) {
                    params[field] = ts[field];
                }
            });

            ts.query.forEach((val, idx) => {
                if (val !== '') {
                    params.query.push(ts.query[idx]);
                    params.fieldClass.push(ts.fieldClass[idx]);
                    params.joinOp.push(ts.joinOp[idx]);
                    params.matchOp.push(ts.matchOp[idx]);
                }
            });

            // CCVM filters are encoded as comma-separated lists
            Object.keys(ts.ccvmFilters).forEach(code => {
                if (ts.ccvmFilters[code] &&
                    ts.ccvmFilters[code][0] !== '') {
                    params[code] = ts.ccvmFilters[code].join(',');
                }
            });

            // Each facet is a JSON encoded blob of class, name, and value
            if (ts.facetFilters.length) {
                params.facets = [];
                ts.facetFilters.forEach(facet => {
                    params.facets.push(JSON.stringify({
                        c : facet.facetClass,
                        n : facet.facetName,
                        v : facet.facetValue
                    }));
                });
            }

            if (ts.copyLocations.length && ts.copyLocations[0] !== '') {
                params.copyLocations = ts.copyLocations.join(',');
            }
        }

        return params;
    }

    /**
     * Creates a new search context from the active route params.
     */
    fromUrlParams(params: ParamMap): CatalogSearchContext {
        const context = new CatalogSearchContext();

        this.applyUrlParams(context, params);

        return context;
    }

    applyUrlParams(context: CatalogSearchContext, params: ParamMap): void {

        // Reset query/filter args.  The will be reconstructed below.
        context.reset();
        let val;

        if (params.get('org')) {
            context.searchOrg = this.org.get(+params.get('org'));
        }

        if (val = params.get('limit')) {
            context.pager.limit = +val;
        }

        if (val = params.get('offset')) {
            context.pager.offset = +val;
        }

        if (val = params.get('sort')) {
            context.sort = val;
        }

        if (val = params.get('global')) {
            context.global = val;
        }

        if (val = params.get('showBasket')) {
            context.showBasket = val;
        }

        if (params.get('marcValue')) {
            context.marcSearch.tags = params.getAll('marcTag');
            context.marcSearch.subfields = params.getAll('marcSubfield');
            context.marcSearch.values = params.getAll('marcValue');
        }

        if (params.get('identQuery')) {
            context.identSearch.value = params.get('identQuery');
            context.identSearch.queryType = params.get('identQueryType');
        }

        if (params.get('browseTerm')) {
            context.browseSearch.value = params.get('browseTerm');
            context.browseSearch.fieldClass = params.get('browseClass');
            if (params.has('browsePivot')) {
                context.browseSearch.pivot = +params.get('browsePivot');
            }
        }

        const ts = context.termSearch;

        // browseEntry and query searches may be facet-limited
        params.getAll('facets').forEach(blob => {
            const facet = JSON.parse(blob);
            ts.addFacet(new FacetFilter(facet.c, facet.n, facet.v));
        });

        if (params.has('hasBrowseEntry')) {

            ts.hasBrowseEntry = params.get('hasBrowseEntry');

        } else if (params.has('query')) {

            // Scalars
            ['format', 'available', 'date1', 'date2',
                'dateOp', 'groupByMetarecord', 'fromMetarecord']
            .forEach(field => {
                if (params.has(field)) {
                    ts[field] = params.get(field);
                }
            });

            // Arrays
            ['query', 'fieldClass', 'joinOp', 'matchOp'].forEach(field => {
                const arr = params.getAll(field);
                if (params.has(field)) {
                    ts[field] = params.getAll(field);
                }
            });

            CATALOG_CCVM_FILTERS.forEach(code => {
                const ccvmVal = params.get(code);
                if (ccvmVal) {
                    ts.ccvmFilters[code] = ccvmVal.split(/,/);
                } else {
                    ts.ccvmFilters[code] = [''];
                }
            });

            if (params.get('copyLocations')) {
                ts.copyLocations = params.get('copyLocations').split(/,/);
            }
        }
    }
}


