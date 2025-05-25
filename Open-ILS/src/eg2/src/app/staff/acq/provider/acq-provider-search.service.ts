
import {Injectable} from '@angular/core';
import {EMPTY, throwError, map} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {EventService} from '@eg/core/event.service';
import {ProviderRecordService} from './provider-record.service';

export interface AcqProviderSearchTerm {
    classes: string[];
    fields: string[];
    op: string;
    value: any;
}

export interface AcqProviderSearch {
    terms: AcqProviderSearchTerm[];
}

@Injectable()
export class AcqProviderSearchService {

    _terms: AcqProviderSearchTerm[] = [];
    firstRun = true;

    constructor(
        private evt: EventService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private providerRecord: ProviderRecordService
    ) {
        this.firstRun = true;
    }

    setSearch(search: AcqProviderSearch) {
        this._terms = search.terms;
        this.firstRun = false;
    }

    generateSearchJoins(): any {
        const joinPart = new Object();
        let class_list = new Array();

        // get all the classes used
        this._terms.forEach(term => { class_list = class_list.concat(term.classes); });

        // filter out acqpro, empty names, and make unique
        class_list = class_list.filter((x, i, a) => x && x !== 'acqpro' && a.indexOf(x) === i);

        // build a join clause for use in the "opts" part of a pcrud query
        class_list.forEach(cls => { joinPart[cls] = {type : 'left' }; });

        if (Object.keys(joinPart).length === 0) { return null; }
        return joinPart;
    }

    generateSearch(filters): any {
        // base query to grab all providers
        const base = { id: { '!=': null } };
        const query: any = new Array();
        query.push(base);

        // handle supplied search terms
        this._terms.forEach(term => {
            if (term.value === '') {
                return;
            }

            // not const because we may want an array
            let query_obj = new Object();
            const query_arr = new Array();

            let op = term.op;
            if (!op) { op = '='; } // just in case

            let val = term.value;
            if (op === 'ilike') {
                val = '%' + val + '%';
            }

            let isOR = false;
            term.fields.forEach( (field, ind) => {
                const curr_cls = term.classes[ind];

                // remove any OUs that the user doesn't have provider view
                // permission for
                if (curr_cls === 'acqpro' && field === 'owner' && op === 'in') {
                    val = val.filter(ou => {
                        return this.providerRecord.getViewOUs().includes(ou);
                    });
                }

                if (ind === 1) {
                    // we're OR'ing in other classes/fields
                    // and this is the first so restructure
                    const first_cls = term.classes[0];
                    isOR = true;
                    let tmp = new Object();
                    if (first_cls) {
                        tmp['+' + first_cls] = query_obj;
                    } else {
                        tmp = query_obj;
                    }

                    query_arr.push(tmp);
                }

                if (curr_cls) {
                    if (isOR) {
                        const tmp = new Object();
                        tmp['+' + curr_cls] = new Object();
                        tmp['+' + curr_cls][field] = new Object();
                        tmp['+' + curr_cls][field][op] = val;
                        query_arr.push(tmp);
                    } else {
                        query_obj['+' + curr_cls] = new Object();
                        query_obj['+' + curr_cls][field] = new Object();
                        query_obj['+' + curr_cls][field][op] = val;
                    }
                } else {
                    if (isOR) {
                        const tmp = new Object();
                        tmp[field] = new Object();
                        tmp[field][op] = val;
                        query_arr.push(tmp);
                    } else {
                        query_obj[field] = new Object();
                        query_obj[field][op] = val;
                    }
                }

            });

            if (isOR) { query_obj = {'-or': query_arr}; }
            query.push(query_obj);
        });

        // handle grid filters
        // note that date filters coming from the grid do not need
        // to worry about __castdate because the grid filter supplies
        // both the start and end times
        const observables = [];
        Object.keys(filters).forEach(filterField => {
            filters[filterField].forEach(condition => {
                query.push(condition);
            });
        });
        return query;
    }

    getDataSource(): GridDataSource {
        const gridSource = new GridDataSource();

        // we'll sort by provder name by default
        gridSource.sort = [{ name: 'name', dir: 'ASC' }];

        gridSource.getRows = (pager: Pager, sort: any[]) => {

            // don't do a search the very first time we
            // get invoked, which is during initialization; we'll
            // let components higher up the change decide whether
            // to submit a search
            if (this.firstRun) {
                this.firstRun = false;
                return EMPTY;
            }

            const joins = this.generateSearchJoins();
            const query = this.generateSearch(gridSource.filters);

            const opts = {};
            if (joins) { opts['join'] = joins; }
            opts['offset'] = pager.offset;
            opts['limit'] = pager.limit;
            opts['au_by_id'] = true;

            if (sort.length > 0) {
                opts['order_by'] = [];
                sort.forEach(sort_clause => {
                    opts['order_by'].push({
                        class: 'acqpro',
                        field: sort_clause.name,
                        direction: sort_clause.dir
                    });
                });
            }

            return this.pcrud.search('acqpro',
                query,
                opts
            ).pipe(
                map(res => {
                    if (this.evt.parse(res)) {
                        throw throwError(res);
                    } else {
                        return res;
                    }
                }),
            );
        };
        return gridSource;
    }
}
