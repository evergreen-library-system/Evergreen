
import {Injectable} from '@angular/core';
import {EMPTY, throwError, map} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {EventService} from '@eg/core/event.service';
import {AttrDefsService} from './attr-defs.service';

const baseIdlClass = {
    lineitem: 'jub',
    purchase_order: 'acqpo',
    picklist: 'acqpl',
    invoice: 'acqinv'
};

const defaultSearch = {
    lineitem: {
        jub: [{
            id: '0',
            __gte: true
        }]
    },
    purchase_order: {
        acqpo: [{
            id: '0',
            __gte: true
        }]
    },
    picklist: {
        acqpl: [{
            id: '0',
            __gte: true
        }]
    },
    invoice: {
        acqinv: [{
            id: '0',
            __gte: true
        }]
    },
};

const searchOptions = {
    lineitem: {
        flesh_attrs: true,
        flesh_cancel_reason: true,
        flesh_notes: true,
        flesh_provider: true,
        flesh_claim_policy: true,
        flesh_queued_record: true,
        flesh_creator: true,
        flesh_editor: true,
        flesh_selector: true,
        flesh_po: true,
        flesh_pl: true,
        flesh_li_details: true,
    },
    purchase_order: {
        flesh_cancel_reason: true,
        flesh_provider: true,
        flesh_owner: true,
        flesh_creator: true,
        flesh_editor: true
    },
    picklist: {
        flesh_lineitem_count: true,
        flesh_owner: true,
        flesh_creator: true,
        flesh_editor: true
    },
    invoice: {
        no_flesh_misc: false,
        flesh_provider: true // and shipper, which is also a provider
    }
};

const operatorMap = {
    '!=': '__not',
    '>': '__gt',
    '>=': '__gte',
    '<=': '__lte',
    '<': '__lt',
    'startswith': '__starts',
    'endswith': '__ends',
    'like': '__fuzzy',
};

export interface AcqSearchTerm {
    field: string;
    op: string;
    value1: string;
    value2: string;
    is_date?: boolean;
}

export interface AcqSearch {
    terms: AcqSearchTerm[];
    conjunction: string;
}

@Injectable()
export class AcqSearchService {

    _terms: AcqSearchTerm[] = [];
    _conjunction = 'all';
    firstRun = true;

    constructor(
        private net: NetService,
        private evt: EventService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private attrDefs: AttrDefsService
    ) {
        this.firstRun = true;
    }

    setSearch(search: AcqSearch) {
        this._terms = search.terms;
        this._conjunction = search.conjunction;
        this.firstRun = false;
    }

    generateAcqSearch(searchType, filters): any {
        const andTerms = JSON.parse(JSON.stringify(defaultSearch[searchType])); // deep copy
        const orTerms = {};
        const coreRecType = Object.keys(defaultSearch[searchType])[0];

        // handle supplied search terms
        this._terms.forEach(term => {
            if (term.value1 === '' && !(term.op === '__isnull' || term.op === '__isnotnull')) {
                return;
            }
            const searchTerm: Object = {};
            const recType = term.field.split(':')[0];
            const searchField = term.field.split(':')[1];
            if (term.op === '__isnull') {
                searchTerm[searchField] = null;
            } else if (term.op === '__isnotnull') {
                searchTerm[searchField] = { '!=' : null };
            } else if (term.op === '__between') {
                searchTerm[searchField] = [term.value1, term.value2];
            } else {
                searchTerm[searchField] = term.value1;
            }
            if (term.op !== '') {
                if (term.op === '__not,__fuzzy') {
                    searchTerm['__not'] = true;
                    searchTerm['__fuzzy'] = true;
                } else {
                    searchTerm[term.op] = true;
                }
            }
            if (term.is_date) {
                searchTerm['__castdate'] = true;
            }
            if (this._conjunction === 'any') {
                if (!(recType in orTerms)) {
                    orTerms[recType] = [];
                }
                orTerms[recType].push(searchTerm);
            } else {
                if (!(recType in andTerms)) {
                    andTerms[recType] = [];
                }
                andTerms[recType].push(searchTerm);
            }
        });

        // handle grid filters
        // note that date filters coming from the grid do not need
        // to worry about __castdate because the grid filter supplies
        // both the start and end times
        const observables = [];
        Object.keys(filters).forEach(filterField => {
            filters[filterField].forEach(condition => {
                const searchTerm: Object = {};
                let filterOp = '=';
                let filterVal = '';
                if (Object.keys(condition).some(x => x === '-not')) {
                    filterOp = Object.keys(condition['-not'][filterField])[0];
                    filterVal = condition['-not'][filterField][filterOp];
                    searchTerm['__not'] = true;
                } else {
                    filterOp = Object.keys(condition[filterField])[0];
                    filterVal = condition[filterField][filterOp];
                    if (filterOp === 'like' && filterVal.length > 1) {
                        if (filterVal[0] === '%' && filterVal[filterVal.length - 1] === '%') {
                            filterVal = filterVal.slice(1, filterVal.length - 1);
                        } else if (filterVal[filterVal.length - 1] === '%') {
                            filterVal = filterVal.slice(0, filterVal.length - 1);
                            filterOp = 'startswith';
                        } else if (filterVal[0] === '%') {
                            filterVal = filterVal.slice(1);
                            filterOp = 'endswith';
                        }
                    }
                }

                if (filterOp in operatorMap) {
                    searchTerm[operatorMap[filterOp]] = true;
                }
                if ((['title', 'author'].indexOf(filterField) > -1) &&
                     (filterField in this.attrDefs.attrDefs)) {
                    if (!('acqlia' in andTerms)) {
                        andTerms['acqlia'] = [];
                    }
                    searchTerm[this.attrDefs.attrDefs[filterField].id()] = filterVal;
                    andTerms['acqlia'].push(searchTerm);
                } else {
                    searchTerm[filterField] = filterVal;
                    andTerms[coreRecType].push(searchTerm);
                }
            });
        });
        return { andTerms: andTerms, orTerms: orTerms };
    }

    getAcqSearchDataSource(searchType: string): GridDataSource {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {

            // don't do a search the very first time we
            // get invoked, which is during initialization; we'll
            // let components higher up the change decide whether
            // to submit a search
            if (this.firstRun) {
                this.firstRun = false;
                return EMPTY;
            }

            const currentSearch = this.generateAcqSearch(searchType, gridSource.filters);

            const opts = { ...searchOptions[searchType] };
            opts['offset'] = pager.offset;
            opts['limit'] = pager.limit;
            opts['au_by_id'] = true;

            if (sort.length > 0) {
                opts['order_by'] = [];
                sort.forEach(sort_clause => {
                    if (searchType === 'lineitem' &&
                        ['title', 'author'].indexOf(sort_clause.name) > -1) {
                        opts['order_by'].push({
                            class: 'acqlia',
                            field: 'attr_value',
                            direction: sort_clause.dir
                        });
                        opts['order_by_attr'] = sort_clause.name;
                    } else {
                        opts['order_by'].push({
                            class: baseIdlClass[searchType],
                            field: sort_clause.name,
                            direction: sort_clause.dir
                        });
                    }
                });
            }

            return this.net.request(
                'open-ils.acq',
                'open-ils.acq.' + searchType + '.unified_search',
                this.auth.token(),
                currentSearch.andTerms,
                currentSearch.orTerms,
                null,
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
