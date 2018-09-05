import {Injectable} from '@angular/core';
import {Observable} from 'rxjs/Observable';
import {mergeMap} from 'rxjs/operators/mergeMap';
import {map} from 'rxjs/operators/map';
import {OrgService} from '@eg/core/org.service';
import {UnapiService} from '@eg/share/catalog/unapi.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogSearchContext, CatalogSearchState} from './search-context';
import {BibRecordService, BibRecordSummary} from './bib-record.service';

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

@Injectable()
export class CatalogService {

    ccvmMap: {[ccvm: string]: IdlObject[]} = {};
    cmfMap: {[cmf: string]: IdlObject} = {};

    // Keep a reference to the most recently retrieved facet data,
    // since facet data is consistent across a given search.
    // No need to re-fetch with every page of search data.
    lastFacetData: any;
    lastFacetKey: string;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private unapi: UnapiService,
        private pcrud: PcrudService,
        private bibService: BibRecordService
    ) {}

    search(ctx: CatalogSearchContext): Promise<void> {
        ctx.searchState = CatalogSearchState.SEARCHING;

        const fullQuery = ctx.compileSearch();

        console.debug(`search query: ${fullQuery}`);

        let method = 'open-ils.search.biblio.multiclass.query';
        if (ctx.isStaff) {
            method += '.staff';
        }

        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.search', method, {
                    limit : ctx.pager.limit + 1,
                    offset : ctx.pager.offset
                }, fullQuery, true
            ).subscribe(result => {
                this.applyResultData(ctx, result);
                ctx.searchState = CatalogSearchState.COMPLETE;
                resolve();
            });
        });
    }

    applyResultData(ctx: CatalogSearchContext, result: any): void {
        ctx.result = result;
        ctx.pager.resultCount = result.count;

        // records[] tracks the current page of bib summaries.
        result.records = [];

        // If this is a new search, reset the result IDs collection.
        if (this.lastFacetKey !== result.facet_key) {
            ctx.resultIds = [];
        }

        result.ids.forEach((blob, idx) => ctx.addResultId(blob[0], idx));
    }

    // Appends records to the search result set as they arrive.
    // Returns a void promise once all records have been retrieved
    fetchBibSummaries(ctx: CatalogSearchContext): Promise<void> {

        const depth = ctx.global ?
            ctx.org.root().ou_type().depth() :
            ctx.searchOrg.ou_type().depth();

        return this.bibService.getBibSummary(
            ctx.currentResultIds(), ctx.searchOrg.id(), depth)
        .pipe(map(summary => {
            // Responses are not necessarily returned in request-ID order.
            const idx = ctx.currentResultIds().indexOf(summary.record.id());
            if (ctx.result.records) {
                // May be reset when quickly navigating results.
                ctx.result.records[idx] = summary;
            }
        })).toPromise();
    }

    fetchFacets(ctx: CatalogSearchContext): Promise<void> {

        if (!ctx.result) {
            return Promise.reject('Cannot fetch facets without results');
        }

        if (this.lastFacetKey === ctx.result.facet_key) {
            ctx.result.facetData = this.lastFacetData;
            return Promise.resolve();
        }

        return new Promise((resolve, reject) => {
            this.net.request('open-ils.search',
                'open-ils.search.facet_cache.retrieve',
                ctx.result.facet_key
            ).subscribe(facets => {
                const facetData = {};
                Object.keys(facets).forEach(cmfId => {
                    const facetHash = facets[cmfId];
                    const cmf = this.cmfMap[cmfId];

                    const cmfData = [];
                    Object.keys(facetHash).forEach(value => {
                        const count = facetHash[value];
                        cmfData.push({value : value, count : count});
                    });

                    if (!facetData[cmf.field_class()]) {
                        facetData[cmf.field_class()] = {};
                    }

                    facetData[cmf.field_class()][cmf.name()] = {
                        cmfLabel : cmf.label(),
                        valueList : cmfData.sort((a, b) => {
                            if (a.count > b.count) { return -1; }
                            if (a.count < b.count) { return 1; }
                            // secondary alpha sort on display value
                            return a.value < b.value ? -1 : 1;
                        })
                    };
                });

                this.lastFacetKey = ctx.result.facet_key;
                this.lastFacetData = ctx.result.facetData = facetData;
                resolve();
            });
        });
    }

    fetchCcvms(): Promise<void> {

        if (Object.keys(this.ccvmMap).length) {
            return Promise.resolve();
        }

        return new Promise((resolve, reject) => {
            this.pcrud.search('ccvm',
                {ctype : CATALOG_CCVM_FILTERS}, {},
                {atomic: true, anonymous: true}
            ).subscribe(list => {
                this.compileCcvms(list);
                resolve();
            });
        });
    }

    compileCcvms(ccvms: IdlObject[]): void {
        ccvms.forEach(ccvm => {
            if (!this.ccvmMap[ccvm.ctype()]) {
                this.ccvmMap[ccvm.ctype()] = [];
            }
            this.ccvmMap[ccvm.ctype()].push(ccvm);
        });

        Object.keys(this.ccvmMap).forEach(cType => {
            this.ccvmMap[cType] =
                this.ccvmMap[cType].sort((a, b) => {
                    return a.value() < b.value() ? -1 : 1;
                });
        });
    }


    fetchCmfs(): Promise<void> {
        // At the moment, we only need facet CMFs.
        if (Object.keys(this.cmfMap).length) {
            return Promise.resolve();
        }

        return new Promise((resolve, reject) => {
            this.pcrud.search('cmf',
                {facet_field : 't'}, {}, {atomic: true, anonymous: true}
            ).subscribe(
                cmfs => {
                    cmfs.forEach(c => this.cmfMap[c.id()] = c);
                    resolve();
                }
            );
        });
    }
}
