import { PcrudService } from '@eg/core/pcrud.service';
import { Pager } from '../util/pager';
import { GridDataSource } from './grid';
import { Observable } from 'rxjs';
import { IdlObject } from '@eg/core/idl.service';

/**
 * A factory function to help build a custom GridDataSource
 */
export function buildPcrudGridDataSource(
    /**
     * The IDL/fieldmapper class you are working with
     */
    fmClass: string,

    /**
     * An instance of the PcrudService
     */
    pcrud: PcrudService,

    /**
     * A function that takes the current state of the Grid Data Source
     * and returns an array of searches (in a format like:
     * [{id: "3"}])
     */
    searchBuilder: (source:GridDataSource) => any[] = basicSearchBuilder,

    /**
     * A function that takes various choices the user has made regarding
     * sorting and paging the grid, and returns an object with information
     * like offset, limit, and order_by
     */
    searchOptsBuilder: (searchOptsFmClass: string, pager: Pager, sort: any[]) => any
    = basicSearchOptsBuilder,

    /**
     * A function that has the same basic API as the PCRUD service's `search`
     * method
     */
    searchFn: (searchFnFmClass: string, searchFnPcrud: PcrudService, search: any, pcrudOps?: any) => Observable<any>
    = basicSearchFn
): GridDataSource {
    searchBuilder ||= basicSearchBuilder;
    searchFn ||= basicSearchFn;
    const source = new GridDataSource();
    source.getRows = (pager: Pager, sort: any[]) => {
        const search = searchBuilder(source);
        const searchOpts = searchOptsBuilder(fmClass, pager, sort);
        return searchFn(fmClass, pcrud, search, searchOpts);
    };
    return source;
}

export function basicSearchBuilder(source:GridDataSource): any[] {
    const search: any[] = new Array();
    Object.keys(source.filters).forEach(key => {
        Object.keys(source.filters[key]).forEach(key2 => {
            search.push(source.filters[key][key2]);
        });
    });
    return search;
}

export function basicSearchOptsBuilder(fmClass: string, pager: Pager, sort: any[]): any {
    const orderBy: any = {};

    if (sort.length) {
        // Sort specified from grid
        orderBy[fmClass] = sort[0].name + ' ' + sort[0].dir;
    }
    return {
        offset: pager.offset,
        limit: pager.limit,
        order_by: orderBy
    };
}

export function basicSearchFn(fmClass: string, pcrud: PcrudService, search: any, searchOpts: any): Observable<IdlObject> {
    if (search.length) {
        return pcrud.search(fmClass, search, searchOpts, {fleshSelectors: true});
    } else {
        return pcrud.retrieveAll(fmClass, searchOpts, {fleshSelectors: true});
    }
}
