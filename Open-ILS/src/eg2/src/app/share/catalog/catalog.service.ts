/* eslint-disable */
/* eslint-disable no-empty, no-magic-numbers */
import {Injectable, EventEmitter} from '@angular/core';
import {Observable, of} from 'rxjs';
import {map, tap, finalize} from 'rxjs/operators';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogSearchContext, CatalogSearchState, CATALOG_CCVM_FILTERS} from './search-context';
import {BibRecordService, BibRecordSummary} from './bib-record.service';
import {BasketService} from './basket.service';
import { ServerStoreService } from '@eg/core/server-store.service';

@Injectable()
export class CatalogService {

    ccvmMap: {[ccvm: string]: IdlObject[]} = {};
    cmfMap: {[cmf: string]: IdlObject} = {};
    copyLocations: IdlObject[];
    copyLocationGroups: IdlObject[];
    libraryGroups: IdlObject[];
    combineLibraryAndLocationGroups: boolean;
    useSearchHighlight: boolean;
    useSearchHighlightDefault = true;

    // Keep a reference to the most recently retrieved facet data,
    // since facet data is consistent across a given search.
    // No need to re-fetch with every page of search data.
    lastFacetData: any;
    lastFacetKey: string;

    // Allow anyone to watch for completed searches.
    onSearchComplete: EventEmitter<CatalogSearchContext>;

    constructor(
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private bibService: BibRecordService,
        private basket: BasketService,
        private store: ServerStoreService

    ) {
        this.net.request(
            'open-ils.search',
            'open-ils.search.staff.location_groups_with_lassos'
        ).toPromise().then(combine => this.combineLibraryAndLocationGroups = !!combine);

        this.onSearchComplete = new EventEmitter<CatalogSearchContext>();
        store.getItem('ui.show_search_highlight').then(result => {this.useSearchHighlight = result ?? this.useSearchHighlightDefault;});
    }

    search(ctx: CatalogSearchContext): Promise<void> {
        ctx.searchState = CatalogSearchState.SEARCHING;

        if (ctx.showBasket) {
            return this.basketSearch(ctx);
        } else if (ctx.marcSearch.isSearchable()) {
            return this.marcSearch(ctx);
        } else if (ctx.identSearch.isSearchable() &&
            ctx.identSearch.queryType === 'item_barcode') {
            return this.barcodeSearch(ctx);
        } else if (
            ctx.isStaff &&
            ctx.identSearch.isSearchable() &&
            ctx.identSearch.queryType === 'identifier|tcn') {
            return this.tcnStaffSearch(ctx);
        } else {
            return this.termSearch(ctx);
        }
    }

    barcodeSearch(ctx: CatalogSearchContext): Promise<void> {
        return this.net.request(
            'open-ils.search',
            'open-ils.search.multi_home.bib_ids.by_barcode',
            ctx.identSearch.value
        ).toPromise().then(ids => {
            // API returns an event for not-found barcodes
            if (!Array.isArray(ids)) { ids = []; }
            const result = {
                count: ids.length,
                ids: ids.map(id => [id])
            };

            this.applyResultData(ctx, result);
            ctx.searchState = CatalogSearchState.COMPLETE;
            this.onSearchComplete.emit(ctx);
        });
    }

    tcnStaffSearch(ctx: CatalogSearchContext): Promise<void> {
        return this.net.request(
            'open-ils.search',
            'open-ils.search.biblio.tcn',
            ctx.identSearch.value, 1
        ).toPromise().then(result => {
            result.ids =  result.ids.map(id => [id]);
            this.applyResultData(ctx, result);
            ctx.searchState = CatalogSearchState.COMPLETE;
            this.onSearchComplete.emit(ctx);
        });
    }


    // "Search" the basket by loading the IDs and treating
    // them like a standard query search results set.
    basketSearch(ctx: CatalogSearchContext): Promise<void> {

        return this.basket.getRecordIds().then(ids => {

            const pageIds =
                ids.slice(ctx.pager.offset, ctx.pager.limit + ctx.pager.offset);

            // Map our list of IDs into a search results object
            // the search context can understand.
            const result = {
                count: ids.length,
                ids: pageIds.map(id => [id])
            };

            this.applyResultData(ctx, result);
            ctx.searchState = CatalogSearchState.COMPLETE;
            this.onSearchComplete.emit(ctx);
        });
    }

    marcSearch(ctx: CatalogSearchContext): Promise<void> {
        let method = 'open-ils.search.biblio.marc';
        if (ctx.isStaff) { method += '.staff'; }

        const queryStruct = ctx.compileMarcSearchArgs();

        return this.net.request('open-ils.search', method, queryStruct)
            .toPromise().then(result => {
            // Match the query search return format
                result.ids = result.ids.map(id => [id]);

                this.applyResultData(ctx, result);
                ctx.searchState = CatalogSearchState.COMPLETE;
                this.onSearchComplete.emit(ctx);
            });
    }

    termSearch(ctx: CatalogSearchContext): Promise<void> {

        let method = 'open-ils.search.biblio.multiclass.query';
        let fullQuery;

        if (ctx.identSearch.isSearchable()) {
            fullQuery = ctx.compileIdentSearchQuery();

        } else {
            fullQuery = ctx.compileTermSearchQuery();

            if (ctx.termSearch.groupByMetarecord
                && !ctx.termSearch.fromMetarecord) {
                method = 'open-ils.search.metabib.multiclass.query';
            }

            if (ctx.termSearch.hasBrowseEntry) {
                this.fetchBrowseEntry(ctx);
            }
        }

        console.debug(`search query: ${fullQuery}`);

        if (ctx.isStaff) {
            method += '.staff';
        }

        return this.net.request(
            'open-ils.search', method, {
                limit : ctx.pager.limit + 1,
                offset : ctx.pager.offset
            }, fullQuery, true
        ).toPromise()
            .then(result => this.applyResultData(ctx, result))
            .then(_ => this.fetchFieldHighlights(ctx))
            .then(_ => {
                ctx.searchState = CatalogSearchState.COMPLETE;
                this.onSearchComplete.emit(ctx);
            });
    }

    // When showing titles linked to a browse entry, fetch
    // the entry data as well so the UI can display it.
    fetchBrowseEntry(ctx: CatalogSearchContext) {
        const ts = ctx.termSearch;

        const parts = ts.hasBrowseEntry.split(',');
        const mbeId = parts[0];
        const cmfId = parts[1];

        this.pcrud.retrieve('mbe', mbeId)
            .subscribe(mbe => ctx.termSearch.browseEntry = mbe);
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

        const org = ctx.global ? ctx.org.root() : ctx.searchOrg;
        const depth = org.ou_type().depth();

        const isMeta = ctx.termSearch.isMetarecordSearch();

        let observable: Observable<BibRecordSummary>;

        const options: any = {pref_ou: ctx.prefOu};

        if (ctx.showResultExtras) {
            options.flesh_copies = true;
            options.copy_depth = depth;
            options.copy_limit = 5;
            options.pref_ou = ctx.prefOu;
        }

        if (ctx.currentLasso()) {
            options.library_group = ctx.currentLasso();
        }

        if (isMeta) {
            observable = this.bibService.getMetabibSummaries(
                ctx.currentResultIds(), ctx.searchOrg.id(), ctx.isStaff, options);
        } else {
            observable = this.bibService.getBibSummaries(
                ctx.currentResultIds(), ctx.searchOrg.id(), ctx.isStaff, options);
        }

        return observable.pipe(map(summary => {
            // Responses are not necessarily returned in request-ID order.
            let idx;
            if (isMeta) {
                idx = ctx.currentResultIds().indexOf(summary.metabibId);
            } else {
                idx = ctx.currentResultIds().indexOf(summary.id);
            }

            if (ctx.result.records) {
                // May be reset when quickly navigating results.
                ctx.result.records[idx] = summary;
            }

            if (ctx.highlightData[summary.id]) {
                summary.displayHighlights = ctx.highlightData[summary.id];
            }
        })).toPromise();
    }

    fetchFieldHighlights(ctx: CatalogSearchContext): Promise<any> {

        let hlMap;

        // Extract the highlight map.  Not all searches have them.
        if ((hlMap = ctx.result)            &&
            (hlMap = hlMap.global_summary)  &&
            (hlMap = hlMap.query_struct)    &&
            (hlMap = hlMap.additional_data) &&
            (hlMap = hlMap.highlight_map)   &&
            (hlMap.length > 0)) {
        } else { return Promise.resolve(); }

        // Return unmodified results if the user's settings disable highlighting
        if (this.useSearchHighlight === false){
            return Promise.resolve();
        }

        let ids;
        if (ctx.getHighlightsFor) {
            ids = [ctx.getHighlightsFor];
        } else {
            // ctx.currentResultIds() returns bib IDs or metabib IDs
            // depending on the search type.  If we have metabib IDs, map
            // them to bib IDs for highlighting.
            ids = ctx.currentResultIds();
            if (ctx.termSearch.groupByMetarecord) {
                // The 4th slot in the result ID reports the master record
                // for the metarecord in question.  Sometimes it's null?
                ids = ctx.result.ids.map(id => id[4]).filter(id => id !== null);
            }
        }

        return this.net.requestWithParamList( // API is list-based
            'open-ils.search',
            'open-ils.search.fetch.metabib.display_field.highlight',
            [hlMap].concat(ids)
        ).pipe(map(fields => {

            if (fields.length === 0) { return; }

            // Each 'fields' collection is an array of display field
            // values whose text is augmented with highlighting markup.
            const highlights = ctx.highlightData[fields[0].source] = {};

            fields.forEach(field => {
                const dfMap = this.cmfMap[field.field].display_field_map();
                if (!dfMap) { return; } // pretty sure this can't happen.

                if (dfMap.multi() === 't') {
                    if (!highlights[dfMap.name()]) {
                        highlights[dfMap.name()] = [];
                    }
                    (highlights[dfMap.name()] as string[]).push(field.highlight);
                } else {
                    highlights[dfMap.name()] = field.highlight;
                }
            });

        })).toPromise();
    }

    fetchFacets(ctx: CatalogSearchContext): Promise<void> {

        if (!ctx.result) {
            return Promise.reject('Cannot fetch facets without results');
        }

        if (!ctx.result.facet_key) {
            return Promise.resolve();
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

    iconFormatLabel(code: string): string {
        if (Object.keys(this.ccvmMap).length) {
            const ccvm = this.ccvmMap.icon_format.filter(
                format => format.code() === code)[0];
            if (ccvm) {
                return ccvm.search_label();
            }
        }
    }

    fetchCmfs(): Promise<void> {
        if (Object.keys(this.cmfMap).length) {
            return Promise.resolve();
        }

        return new Promise((resolve, reject) => {
            this.pcrud.search('cmf',
                {'-or': [{facet_field : 't'}, {display_field: 't'}]},
                {flesh: 1, flesh_fields: {cmf: ['display_field_map']}},
                {atomic: true, anonymous: true}
            ).subscribe(
                cmfs => {
                    cmfs.forEach(c => this.cmfMap[c.id()] = c);
                    resolve();
                }
            );
        });
    }

    fetchCopyLocations(contextOrg: number | IdlObject): Promise<any> {
        const contextOrgId: any = this.org.get(contextOrg).id();

        // we ordinarily want the shelving locations associated with
        // all ancestors and descendants of the context OU, but
        // if the context OU is the root, we intentionally want
        // only the ones owned by the root OU
        const orgIds: any[] = contextOrgId === this.org.root().id()
            ? [contextOrgId]
            : this.org.fullPath(contextOrg, true);

        this.copyLocations = [];

        return this.pcrud.search('acpl',
            {deleted: 'f', opac_visible: 't', owning_lib: orgIds},
            {order_by: {acpl: 'name'}},
            {anonymous: true}
        ).pipe(tap(loc => this.copyLocations.push(loc))).toPromise();
    }

    fetchCopyLocationGroups(contextOrg: number | IdlObject): Promise<any> {
        const contextOrgId: any = this.org.get(contextOrg).id();
        const orgIds: any[] = this.org.fullPath(contextOrg, true);

        this.copyLocationGroups = [];

        return this.pcrud.search('acplg',
            {opac_visible: 't', owner: orgIds},
            {order_by: [{class: "acplg", field: "pos"}, {class: "acplg", field: "name"}]},
            {anonymous: true}
        ).pipe(tap(loc => this.copyLocationGroups.push(loc))).toPromise();
    }

    fetchLibraryGroups(contextOrg: number | IdlObject): Promise<any> {
        const contextOrgId: any = this.org.get(contextOrg).id();

        this.libraryGroups = [];

        return this.net.request(
            'open-ils.search',
            'open-ils.search.fetch_context_library_groups',
            contextOrgId
        ).pipe(tap(loc => this.libraryGroups.push(loc))).toPromise();
    }

    browse(ctx: CatalogSearchContext): Observable<any> {
        ctx.searchState = CatalogSearchState.SEARCHING;
        const bs = ctx.browseSearch;

        let method = 'open-ils.search.browse';
        if (ctx.isStaff) {
            method += '.staff';
        }

        return this.net.request(
            'open-ils.search',
            'open-ils.search.browse.staff', {
                browse_class: bs.fieldClass,
                term: bs.value,
                limit : ctx.pager.limit,
                pivot: bs.pivot,
                org_unit: ctx.searchOrg.id()
            }
        ).pipe(
            tap(result => ctx.searchState = CatalogSearchState.COMPLETE),
            finalize(() => this.onSearchComplete.emit(ctx))
        );
    }

    cnBrowse(ctx: CatalogSearchContext): Observable<any> {
        ctx.searchState = CatalogSearchState.SEARCHING;
        const cbs = ctx.cnBrowseSearch;

        return this.net.request(
            'open-ils.supercat',
            'open-ils.supercat.call_number.browse',
            cbs.value, ctx.searchOrg.shortname(), cbs.limit, cbs.offset
        ).pipe(tap(result => ctx.searchState = CatalogSearchState.COMPLETE));
    }

    orgOrLassoName(itemCount: any): Observable<string> {
        if (itemCount.org_unit && itemCount.org_unit > 0) {
            return of(this.org.get(itemCount.org_unit)?.shortname());
        } else if (itemCount.library_group) {
            return this.getLasso(itemCount.library_group).pipe(map(lasso => lasso.name()));
        }
        return of('');
    }

    private getLasso(lassoId): Observable<IdlObject> {
        if (this.libraryGroups.some((group) => group.id() == lassoId)) {
            return of(this.libraryGroups.find((group) => group.id() == lassoId));
        }
        return this.pcrud.retrieve('lasso', lassoId);
    }
}
