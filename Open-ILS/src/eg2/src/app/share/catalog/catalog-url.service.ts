import {Injectable} from '@angular/core';
import {ParamMap} from '@angular/router';
import {OrgService} from '@eg/core/org.service';
import {CatalogSearchContext, FacetFilter} from './search-context';
import {CATALOG_CCVM_FILTERS} from './catalog.service';

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

        const params = {
            query: [],
            fieldClass: [],
            joinOp: [],
            matchOp: [],
            facets: [],
            identQuery: null,
            identQueryType: null,
            org: null,
            limit: null,
            offset: null
        };

        params.org = context.searchOrg.id();

        params.limit = context.pager.limit;
        if (context.pager.offset) {
            params.offset = context.pager.offset;
        }

        // These fields can be copied directly into place
        ['format', 'sort', 'available', 'global', 'identQuery', 'identQueryType']
        .forEach(field => {
            if (context[field]) {
                // Only propagate applied values to the URL.
                params[field] = context[field];
            }
        });

        if (params.identQuery) {
            // Ident queries (e.g. tcn search) discards all remaining filters
            return params;
        }

        context.query.forEach((q, idx) => {
            ['query', 'fieldClass', 'joinOp', 'matchOp'].forEach(field => {
                // Propagate all array-based fields regardless of
                // whether a value is applied to ensure correct
                // correlation between values.
                params[field][idx] = context[field][idx];
            });
        });

        // CCVM filters are encoded as comma-separated lists
        Object.keys(context.ccvmFilters).forEach(code => {
            if (context.ccvmFilters[code] &&
                context.ccvmFilters[code][0] !== '') {
                params[code] = context.ccvmFilters[code].join(',');
            }
        });

        // Each facet is a JSON encoded blob of class, name, and value
        context.facetFilters.forEach(facet => {
            params.facets.push(JSON.stringify({
                c : facet.facetClass,
                n : facet.facetName,
                v : facet.facetValue
            }));
        });

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

        // These fields can be copied directly into place
        ['format', 'sort', 'available', 'global', 'identQuery', 'identQueryType']
        .forEach(field => {
            const val = params.get(field);
            if (val !== null) {
                context[field] = val;
            }
        });

        if (params.get('limit')) {
            context.pager.limit = +params.get('limit');
        }

        if (params.get('offset')) {
            context.pager.offset = +params.get('offset');
        }

        ['query', 'fieldClass', 'joinOp', 'matchOp'].forEach(field => {
            const arr = params.getAll(field);
            if (arr && arr.length) {
                context[field] = arr;
            }
        });

        CATALOG_CCVM_FILTERS.forEach(code => {
            const val = params.get(code);
            if (val) {
                context.ccvmFilters[code] = val.split(/,/);
            } else {
                context.ccvmFilters[code] = [''];
            }
        });

        params.getAll('facets').forEach(blob => {
            const facet = JSON.parse(blob);
            context.addFacet(new FacetFilter(facet.c, facet.n, facet.v));
        });

        if (params.get('org')) {
            context.searchOrg = this.org.get(+params.get('org'));
        }
    }
}
