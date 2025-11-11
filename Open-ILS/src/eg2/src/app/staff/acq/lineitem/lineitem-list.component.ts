/* eslint-disable */
/* eslint-disable rxjs/no-nested-subscribe */
import {Component, OnInit, OnDestroy, Input, ViewChild, ChangeDetectorRef, OnChanges, SimpleChanges, NgZone} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {takeWhile, firstValueFrom, lastValueFrom, from, of, Subscription, Subject} from 'rxjs';
import {takeUntil, defaultIfEmpty, debounceTime, tap, concatMap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {EgEvent, EventService} from '@eg/core/event.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {LineitemService, LINEITEM_DISPOSITION} from './lineitem.service';
import {PoService} from '../po/po.service';
import {InvoiceService} from '../invoice/invoice.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {StringComponent} from '@eg/share/string/string.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {CancelDialogComponent} from './cancel-dialog.component';
import {DeleteLineitemsDialogComponent} from './delete-lineitems-dialog.component';
import {AddCopiesDialogComponent} from './add-copies-dialog.component';
import {BibFinderDialogComponent} from './bib-finder-dialog.component';
import {BatchUpdateCopiesDialogComponent} from './batch-update-copies-dialog.component';
import {LinkInvoiceDialogComponent} from './link-invoice-dialog.component';
import {ExportAttributesDialogComponent} from './export-attributes-dialog.component';
import {ClaimPolicyDialogComponent} from './claim-policy-dialog.component';
import {ManageClaimsDialogComponent} from './manage-claims-dialog.component';
import {LineitemAlertDialogComponent} from './lineitem-alert-dialog.component';
import {AddExtraItemsForOrderDialogComponent} from './add-extra-items-for-order-dialog.component';

const DELETABLE_STATES = [
    'new', 'selector-ready', 'order-ready', 'approved', 'pending-order'
];

const DEFAULT_SORT_ORDER = 'li_id_asc';
const SORT_ORDER_MAP = {
    li_id_asc:  { 'order_by': [{'class': 'jub', 'field': 'id', 'direction': 'ASC'}] },
    li_id_desc: { 'order_by': [{'class': 'jub', 'field': 'id', 'direction': 'DESC'}] },
    li_expected_recv_time_asc: { 'order_by': [{'class': 'jub', 'field': 'expected_recv_time', 'direction': 'ASC'}] },
    li_expected_recv_time_desc: { 'order_by': [{'class': 'jub', 'field': 'expected_recv_time', 'direction': 'DESC'}] },
    title_asc:  { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'ASC'}], 'order_by_attr': 'title' },
    title_desc: { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'DESC'}], 'order_by_attr': 'title' },
    author_asc:  { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'ASC'}], 'order_by_attr': 'author' },
    author_desc: { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'DESC'}], 'order_by_attr': 'author' },
    publisher_asc:  { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'ASC'}], 'order_by_attr': 'publisher' },
    publisher_desc: { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'DESC'}], 'order_by_attr': 'publisher' },
    order_ident_asc:  { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'ASC'}],
        'order_by_attr': ['isbn', 'issn', 'upc'] },
    order_ident_desc: { 'order_by': [{'class': 'acqlia', 'field': 'attr_value', 'direction': 'DESC'}],
        'order_by_attr': ['isbn', 'issn', 'upc'] },
};

@Component({
    templateUrl: 'lineitem-list.component.html',
    selector: 'eg-lineitem-list',
    styleUrls: ['lineitem-list.component.css']
})
export class LineitemListComponent implements OnInit, OnDestroy, OnChanges {

    private permissions: any;
    picklistId: number = null;
    @Input() poId: number = null; // can also get via a route param
    @Input() lids: IdlObject[] = null;
    @Input() batchReceiveMode = false;
    @Input() batchClaimMode = false;
    @Input() defaultSortOrder: string = null;
    @Input() persistKeySuffix = '';
    invoiceEntryMap: any = {};
    lineitemDetailSelectionMap: any = {};
    lineitemDetailCountMap: {[key: number]: number} = {};
    observables: { [key: string]: Subject<{ li: any, newValue: any }> } = {};
    lineItemObservables: { [lineItemId: number]: { [fieldName: string]: Subject<{ li: IdlObject, newValue: any }> } } = {};

    private destroy$ = new Subject<void>(); // for takeUntil's

    previousLineitemDetailCountMap: {[key: number]: number} = {};
    poWasActivated = false;
    poSubscription: Subscription;
    invoiceSubscription: Subscription;
    recordId: number = null; // lineitems related to a bib.

    loading = false;
    pager: Pager = new Pager();
    pageOfLineitems: IdlObject[] = [];
    lineitemIds: number[] = [];

    saving = false;
    progressMax = 0;
    progressValue = 0;

    // Selected lineitems
    selected: {[id: number]: boolean} = {};

    // Order identifier type per lineitem
    orderIdentTypes: {[id: number]: 'isbn' | 'issn' | 'upc'} = {};

    // Copy counts per lineitem
    existingCopyCounts: {[id: number]: number} = {};

    // Squash these down to an easily traversable data set to avoid
    // a lot of repetitive looping.
    liMarcAttrs: {[id: number]: {[name: string]: IdlObject[]}} = {};

    // sorting and filtering
    sortOrder = this.defaultSortOrder || DEFAULT_SORT_ORDER;
    showFilterSort = false;
    filterField = '';
    filterOperator = '';
    filterValue = '';
    filterApplied = false;

    searchTermDatatypes = {
        'id': 'id',
        'state': 'state',
        'acqlia:title': 'text',
        'acqlia:author': 'text',
        'acqlia:publisher': 'text',
        'acqlia:pubdate': 'text',
        'acqlia:isbn': 'text',
        'acqlia:issn': 'text',
        'acqlia:upc': 'text',
        'claim_count': 'number',
        'item_count': 'number',
        'estimated_unit_price': 'money',
    };
    dateLikeSearchFields = {
        'acqlia:pubdate': true,
    };

    batchNote: string;
    noteIsPublic = false;
    batchSelectPage = false;
    batchSelectAll = false;
    showNotesFor: number;
    expandLineitem: {[id: number]: boolean} = {};
    expandAll = false;
    action = '';
    batchFailure: EgEvent;
    focusLi: number;
    firstLoad = true; // using this to ensure that we avoid loading the LI table
    // until the page size and sort order WS settings have been fetched
    // TODO: route guard might be better

    @ViewChild('cancelDialog') cancelDialog: CancelDialogComponent;
    @ViewChild('deleteLineitemsDialog') deleteLineitemsDialog: DeleteLineitemsDialogComponent;
    @ViewChild('addCopiesDialog') addCopiesDialog: AddCopiesDialogComponent;
    @ViewChild('bibFinderDialog') bibFinderDialog: BibFinderDialogComponent;
    @ViewChild('batchUpdateCopiesDialog') batchUpdateCopiesDialog: BatchUpdateCopiesDialogComponent;
    @ViewChild('linkInvoiceDialog') linkInvoiceDialog: LinkInvoiceDialogComponent;
    @ViewChild('exportAttributesDialog') exportAttributesDialog: ExportAttributesDialogComponent;
    @ViewChild('claimPolicyDialog') claimPolicyDialog: ClaimPolicyDialogComponent;
    @ViewChild('manageClaimsDialog') manageClaimsDialog: ManageClaimsDialogComponent;
    @ViewChild('lineItemsUpdatedString', { static: false }) lineItemsUpdatedString: StringComponent;
    @ViewChild('noActionableLIs', { static: true }) private noActionableLIs: AlertDialogComponent;
    @ViewChild('selectorReadyConfirmDialog', { static: true }) selectorReadyConfirmDialog: ConfirmDialogComponent;
    @ViewChild('orderReadyConfirmDialog', { static: true }) orderReadyConfirmDialog: ConfirmDialogComponent;
    @ViewChild('confirmAlertsDialog') confirmAlertsDialog: LineitemAlertDialogComponent;
    @ViewChild('confirmExtraItemsDialog') confirmExtraItemsDialog: AddExtraItemsForOrderDialogComponent;
    @ViewChild('stopPercentAlertDialog') stopPercentAlertDialog: AlertDialogComponent;
    @ViewChild('stopPercentConfirmDialog') stopPercentConfirmDialog: ConfirmDialogComponent;
    @ViewChild('warnPercentConfirmDialog') warnPercentConfirmDialog: ConfirmDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private changeDetector: ChangeDetectorRef,
        private zone: NgZone,
        private evt: EventService,
        private net: NetService,
        private perm: PermService,
        private auth: AuthService,
        private org: OrgService,
        private store: ServerStoreService,
        private idl: IdlService,
        private toast: ToastService,
        private holdings: HoldingsService,
        private liService: LineitemService,
        private poService: PoService,
        private invoiceService: InvoiceService
    ) {}

    ngOnInit() {

        console.debug('LineitemListComponent, sortOrder',this.sortOrder);

        this.loadPerms();

        this.liService.getLiAttrDefs();

        this.route.queryParamMap.subscribe((params: ParamMap) => {
            this.pager.offset = +params.get('offset');
            this.pager.limit = +params.get('limit');
            if (!this.firstLoad) {
                this.load();
            }
        });

        this.route.fragment.subscribe((fragment: string) => {
            const id = Number(fragment);
            if (id > 0) { this.focusLineitem(id); }
        });

        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            this.picklistId = +params.get('picklistId');
            if (!this.poId) { // already got it via the selector
                this.poId = +params.get('poId');
            }
            this.recordId = +params.get('recordId');
            if (!this.firstLoad) {
                this.load();
            }
        });

        this.store.getItem('acq.lineitem.page_size'+this.persistKeySuffix).then(count => {
            // eslint-disable-next-line no-magic-numbers
            this.pager.setLimit(count || 20);
            this.store.getItem('acq.lineitem.sort_order'+this.persistKeySuffix).then(sortOrder => {
                if (sortOrder && (sortOrder in SORT_ORDER_MAP)) {
                    this.sortOrder = sortOrder;
                } else {
                    this.sortOrder = this.defaultSortOrder || DEFAULT_SORT_ORDER;
                }
                this.load();
                this.firstLoad = false;
            });
        });

        this.invoiceSubscription = this.invoiceService.invoiceRetrieved.subscribe(_ => {
            if (!this.firstLoad) {
                this.load();
            }
        });

        this.poSubscription = this.poService.poRetrieved.subscribe(_ => {
            // console.log('LineitemListComponent, poRetrieved emitted', retrievedPo);
            if (this.po()) {
                // console.log('LineitemListComponent, this.po()',this.po());
                if (this.po()) {
                    this.poWasActivated = this.po().order_date() ? true : false;
                }
            }
        });

        console.debug('LineitemListComponent, this',this);
    }

    invoice() {
        return this.invoiceService.currentInvoice;
    }

    async loadPerms(): Promise<void> {
        if (this.permissions) {
            return;
        }
        this.permissions = await this.perm.hasWorkPermAt(['ACQ_ALLOW_OVERSPEND'], true);
    }

    ngOnDestroy() {
        this.destroy$.next();
        this.destroy$.complete();
        this.poSubscription.unsubscribe();
        this.invoiceSubscription.unsubscribe();
    }

    po(): IdlObject {
        return this.poService.currentPo;
    }

    pageSizeChange(count: number) {
        this.store.setItem('acq.lineitem.page_size'+this.persistKeySuffix, count).then(_ => {
            this.pager.setLimit(count);
            this.pager.toFirst();
            this.goToPage();
        });
    }

    sortOrderChange(sortOrder: string) {
        this.store.setItem('acq.lineitem.sort_order'+this.persistKeySuffix, sortOrder).then(_ => {
            this.sortOrder = sortOrder;
            if (this.pager.isFirstPage()) {
                this.load();
            } else {
                this.pager.toFirst();
                this.goToPage();
            }
        });
    }

    filterFieldChange(event) {
        this.filterOperator = '';
        if (this.filterField === 'state') {
            this.filterValue = '';
        }
        this.filterField = event;
    }

    filterOperatorChange() {
        // empty for now
    }

    canApplyFilter(): boolean {
        if (this.filterField !== '' &&
            this.filterValue !== '') {
            return true;
        } else {
            return false;
        }
    }

    applyFilter() {
        this.filterApplied = true;
        if (this.pager.isFirstPage()) {
            this.load();
        } else {
            this.pager.toFirst();
            this.goToPage();
        }
    }

    resetFilter() {
        this.filterField = '';
        this.filterOperator = '';
        this.filterValue = '';
        if (this.filterApplied) {
            this.filterApplied = false;
            if (this.pager.isFirstPage()) {
                this.load();
            } else {
                this.pager.toFirst();
                this.goToPage();
            }
        }
    }

    // Focus the selected lineitem, which may not yet exist in the
    // DOM for focusing.
    focusLineitem(id?: number) {
        if (id !== undefined) { this.focusLi = id; }
        if (this.focusLi) {
            const node = document.getElementById('' + this.focusLi);
            if (node) { node.scrollIntoView(true); }
        }
    }

    load(): Promise<any> {
        // Remove change handlers for old line items
        if (this.pageOfLineitems) {
            this.pageOfLineitems.forEach(li => this.removeChangeHandlers(li));
        }

        this.pageOfLineitems = [];

        if (!this.loading && this.pager.limit &&
            (this.poId || this.picklistId || this.recordId || this.invoice() || this.lids)) {

            this.loading = true;

            return this.loadIds()
                .then(_ => this.loadPage())
                .then(_ => this.loading = false)
                .catch(_ => {}); // re-route while page is loading
        }

        // We have not collected enough data to proceed.
        return Promise.resolve();

    }

    loadIds(): Promise<any> {
        this.lineitemIds = [];

        const searchTerms = {};
        const opts = { limit: 10000 };

        if (this.picklistId) {
            Object.assign(searchTerms, { jub: [ { picklist: this.picklistId } ] });
        } else if (this.recordId) {
            Object.assign(searchTerms, { jub: [ { eg_bib_id: this.recordId } ] });
        } else if (this.invoice() && this.invoice().entries()) {
            // Object.assign(searchTerms, { acqinv: [ { id: this.invoice().id() } ] });
            Object.assign(searchTerms, {
                jub: [
                    {
                        id: this.invoice().entries().map(e =>
                            typeof e.lineitem() === 'number' ? e.lineitem() : e.lineitem().id()
                        )
                    }
                ]
            });
        } else if (this.lids) {
            Object.assign(searchTerms, {
                jub: [
                    {
                        id: Array.from(new Set(
                            this.lids.map(lid => typeof lid.lineitem() === 'number' ? lid.lineitem() : lid.lineitem().id() )
                        ))
                    }
                ]
            });
        } else {
            Object.assign(searchTerms, { jub: [ { purchase_order: this.poId } ] });
        }

        if (this.batchReceiveMode) {
            if (!searchTerms['jub']) {
                searchTerms['jub'] = [];
            }
            searchTerms['jub'].push( { __not: true, state: ['received','cancelled'] } );
        }

        if (this.filterApplied) {
            this._handleFiltering(searchTerms);
        }

        if (!(this.sortOrder in SORT_ORDER_MAP)) {
            this.sortOrder = this.defaultSortOrder || DEFAULT_SORT_ORDER;
        }
        Object.assign(opts, SORT_ORDER_MAP[this.sortOrder]);

        let _doingClientSort = false;
        if (this.filterField === 'item_count' ||
            this.filterField === 'claim_count') {
            opts['flesh_li_details'] = true;
        }
        if (this.sortOrder === 'title_asc'      ||
            this.sortOrder === 'title_desc'     ||
            this.sortOrder === 'author_asc'     ||
            this.sortOrder === 'author_desc'    ||
            this.sortOrder === 'publisher_asc'  ||
            this.sortOrder === 'publisher_desc') {
            // if we're going to sort by an attribute, we'll need
            // to actually fetch LI attributes so that we can
            // do a client-side sorting pass that ignores
            // articles and attempts international collation
            _doingClientSort = true;
            opts['flesh_attrs'] = true;
        } else {
            if (!opts['flesh_li_details']) {
                opts['id_list'] = true;
            }
        }

        console.debug('LineitemListComponent, searchTerms',searchTerms);
        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem.unified_search.atomic',
            this.auth.token(),
            searchTerms, // "and" terms
            {},          // "or" terms
            null,
            opts
        ).toPromise().then(resp => {
            console.debug('LineitemListComponent, unified_search response',resp);
            let _mustDeflesh = false;
            if (this.filterField === 'item_count') {
                _mustDeflesh = true;
                if (!isNaN(Number(this.filterValue))) {
                    const num = Number(this.filterValue);
                    resp = resp.filter(l => {
                        if (this.filterOperator === '' && l.item_count() === num) {
                            return true;
                        } else if (this.filterOperator === '__not' && l.item_count() !== num) {
                            return true;
                        } else if (this.filterOperator === '__gte' && l.item_count() >= num) {
                            return true;
                        } else if (this.filterOperator === '__lte' && l.item_count() <= num) {
                            return true;
                        } else {
                            return false;
                        }
                    });
                }
            } else if (this.filterField === 'claim_count') {
                _mustDeflesh = true;
                if (!isNaN(Number(this.filterValue))) {
                    const num = Number(this.filterValue);
                    resp.forEach(
                        l => l['_claim_count'] = l.lineitem_details().reduce(
                            (a, b) => (a ? a.claims().length : 0) + b.claims().length, 0
                        )
                    );
                    resp = resp.filter(l => {
                        if (this.filterOperator === '' && l['_claim_count'] === num) {
                            return true;
                        } else if (this.filterOperator === '__not' && l['_claim_count'] !== num) {
                            return true;
                        } else if (this.filterOperator === '__gte' && l['_claim_count'] >= num) {
                            return true;
                        } else if (this.filterOperator === '__lte' && l['_claim_count'] <= num) {
                            return true;
                        } else {
                            return false;
                        }
                    });
                    resp.forEach(l => delete l['_claim_count']);
                }
            }
            if (_doingClientSort) {
                const sortOrder = this.sortOrder;
                const liService = this.liService;
                // eslint-disable-next-line no-inner-declarations
                function _compareLIs(a, b) {
                    const direction = sortOrder.match(/_asc$/) ? 'asc' : 'desc';
                    const field = sortOrder.replace(/_asc|_desc$/, '');

                    const a_val = liService.getLISortKey(a, field);
                    const b_val = liService.getLISortKey(b, field);

                    if (direction === 'asc') {
                        return  liService.nullableCompare(a_val, b_val);
                    } else {
                        return -liService.nullableCompare(a_val, b_val);
                    }
                }
                this.lineitemIds = resp.sort(_compareLIs).map(l => Number(l.id()));
            } else {
                if (_mustDeflesh) {
                    this.lineitemIds = resp.map(l => Number(l.id()));
                } else {
                    this.lineitemIds = resp.map(i => Number(i));
                }
            }
            if (this.batchReceiveMode || this.batchClaimMode) {
                this.lineitemIds.forEach( (lidId: number) => {
                    this.lineitemDetailCountMap[lidId] ||= 0;
                    this.lineitemDetailSelectionMap[lidId] ||= {};
                });
            }
            this.pager.resultCount = resp.length;
        });
    }

    _handleFiltering(searchTerms: any) {
        const searchTerm: Object = {};
        const filterField = this.filterField;
        let filterOp = this.filterOperator;
        let filterVal = this.filterValue;

        if (filterField === 'item_count' ||
            filterField === 'claim_count') {
            return;
        }

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

        if (filterOp !== '') {
            searchTerm[filterOp] = true;
        }

        if (filterField.match(/^acqlia:/)) {
            const attrName = (filterField.split(':'))[1];
            const def = this.liService.liAttrDefs.filter(
                d => d.code() === attrName)[0];
            if (def) {
                searchTerm[def.id()] = filterVal;
                searchTerms['acqlia'] = [ searchTerm ];
            }
        } else {
            searchTerm[filterField] = filterVal;
            if (!searchTerms['jub']) {
                searchTerms['jub'] = [];
            }
            searchTerms['jub'].push(searchTerm);
        }
    }

    goToPage() {
        this.focusLi = null;
        this.router.navigate([], {
            relativeTo: this.route,
            queryParamsHandling: 'merge',
            fragment: null,
            queryParams: {
                offset: this.pager.offset,
                limit: this.pager.limit
            }
        });
    }

    loadPage(): Promise<any> {
        return this.jumpToLiPage()
            .then(_ => this.loadPageOfLis())
            .then(_ => this.setBatchSelect())
            .then(_ => setTimeout(() => this.focusLineitem()));
    }

    jumpToLiPage(): Promise<boolean> {
        if (!this.focusLi) { return Promise.resolve(true); }

        const idx = this.lineitemIds.indexOf(this.focusLi);
        if (idx === -1) { return Promise.resolve(true); }

        const offset = Math.floor(idx / this.pager.limit) * this.pager.limit;

        return this.router.navigate(['./'], {
            relativeTo: this.route,
            queryParams: {offset: offset, limit: this.pager.limit},
            fragment: '' + this.focusLi
        });
    }

    loadPageOfLis(use_cache = true): Promise<any> {
        // Remove change handlers for old line items, if any
        if (this.pageOfLineitems) {
            this.pageOfLineitems.forEach(li => this.removeChangeHandlers(li));
        }

        this.pageOfLineitems = [];

        const ids = this.lineitemIds.slice(
            this.pager.offset, this.pager.offset + this.pager.limit)
            .filter(id => id !== undefined).filter(id => !Number.isNaN(id)) || [];

        if (ids.length === 0) { return Promise.resolve(); }

        if (use_cache && this.pageOfLineitems.length === ids.length) {
            // All entries found in the cache
            return Promise.resolve();
        }

        this.pageOfLineitems = []; // reset

        const options = {fromCache: use_cache, toCache: use_cache};
        if (this.invoice()) {
            options['fleshMore'] = {'flesh_invoice_entries': true};
            options['fromCache'] = false;
        }
        console.debug('LineitemListComponent, loadPageOfLis',ids, options);
        return this.liService.getFleshedLineitems(
            ids, options)
            .pipe(tap(struct => {
                console.debug('LineitemListComponent, struct', struct);
                console.debug('LineitemListComponent, struct.lineitem.invoice_entries()', struct.lineitem.invoice_entries());
                if (this.invoice()) {
                    const newEntries = (this.invoice().entries()||[]).filter(
                        (e: IdlObject) => e.isnew() && (typeof e.lineitem() === 'number' ? e.lineitem() : e.lineitem().id()) === struct.lineitem.id() );
                    console.debug('LineitemListComponent. newEntries', newEntries);
                    let filteredEntries = [];
                    if (struct.lineitem.invoice_entries()) {
                        filteredEntries = struct.lineitem.invoice_entries()
                            .filter((entry: IdlObject) => entry.invoice() === this.invoice().id());
                    }
                    console.debug('LineitemListComponent. filteredEntries', filteredEntries);
                    const entries = filteredEntries.concat( newEntries );
                    if (entries.length) {
                        this.invoiceEntryMap[struct.lineitem.id()] = entries[0];
                    }
                    if (entries.length > 1) {
                        console.warn('LineitemListComponent: lineitem has multiple invoice_entries for a given invoice',struct.lineitem, entries);
                    }
                    struct.lineitem.invoice_entries(entries);
                    this.invoiceService.changeNotify();
                    console.debug('LineitemListComponent, entries',entries);
                }
                if (this.invoice() || this.batchReceiveMode /* || this.batchClaimMode */) {
                    let filteredDetails = struct.lineitem.lineitem_details() || [];
                    if (filteredDetails.length) {
                        if (this.batchReceiveMode && struct.lineitem.lineitem_details()) {
                            filteredDetails = filteredDetails
                                .filter(detail => !detail.recv_time() && !detail.cancel_reason());
                        }
                    }
                    struct.lineitem.lineitem_details(filteredDetails);
                    this.invoiceService.changeNotify();
                    console.debug('LineitemListComponent, filteredDetails',filteredDetails);
                }
                if (this.lids) {
                    let filteredDetails = struct.lineitem.lineitem_details() || [];
                    if (filteredDetails.length) {
                        filteredDetails = filteredDetails
                            .filter(detail => this.lids.map( acrLid => acrLid.lineitem_detail() ).includes(detail.id()) );
                    }
                    struct.lineitem.lineitem_details(filteredDetails);
                    console.debug('LineitemListComponent, filteredDetails',filteredDetails);
                }
                console.debug('LineitemListComponent, lineitem in list',struct.lineitem);
                this.ingestOneLi(struct.lineitem);
                this.applyChangeHandlers(struct.lineitem);
                this.existingCopyCounts[struct.id] = struct.existing_copies;
            })).toPromise();
    }

    ingestOneLi(li: IdlObject, replace?: boolean) {
        this.liMarcAttrs[li.id()] = {};

        if (this.batchReceiveMode || this.batchClaimMode) {
            this.lineitemDetailSelectionMap[li.id()] ||= {};
            (li.lineitem_details() || []).forEach( (lid: IdlObject) => {
                this.lineitemDetailSelectionMap[li.id()][lid.id()] ||= false;
            });
        }
        if (this.expandAll) {
            this.expandLineitem[li.id()] = true;
        } else {
            this.expandLineitem[li.id()] = false;
        }

        li.attributes().forEach(attr => {
            const name = attr.attr_name();
            this.liMarcAttrs[li.id()][name] =
                this.liService.getAttributes(
                    li, name, 'lineitem_marc_attr_definition');
        });

        const ident = this.liService.getOrderIdent(li);
        this.orderIdentTypes[li.id()] = ident ? ident.attr_name() : 'isbn';

        // newest to oldest
        li.lineitem_notes(li.lineitem_notes().sort(
            (n1, n2) => n1.create_time() < n2.create_time() ? 1 : -1));

        if (replace) {
            for (let idx = 0; idx < this.pageOfLineitems.length; idx++) {
                if (this.pageOfLineitems[idx].id() === li.id()) {
                    this.pageOfLineitems[idx] = li;
                    break;
                }
            }
        } else {
            this.pageOfLineitems.push(li);
        }

        // Remove any 'new' lineitem details which may have been added
        // and left unsaved on the copies page
        li.lineitem_details(li.lineitem_details().filter(d => !d.isnew()));
    }

    // First matching attr
    displayAttr(li: IdlObject, name: string): string {
        return (
            this.liMarcAttrs[li.id()][name] &&
            this.liMarcAttrs[li.id()][name][0]
        ) ? this.liMarcAttrs[li.id()][name][0].attr_value() : '';
    }

    // All matching attrs
    attrs(li: IdlObject, name: string, attrType?: string): IdlObject[] {
        return this.liService.getAttributes(li, name, attrType);
    }

    jacketIdent(li: IdlObject): string {
        return this.displayAttr(li, 'isbn') || this.displayAttr(li, 'upc');
    }

    // Order ident options are pulled from the MARC, but the ident
    // value proper is stored as a local attr def.
    identOptions(li: IdlObject): ComboboxEntry[] {
        const otype = this.orderIdentTypes[li.id()];

        if (this.liMarcAttrs[li.id()][otype]) {
            return this.liMarcAttrs[li.id()][otype].map(
                attr => ({id: attr.id(), label: attr.attr_value()}));
        }

        return [];
    }

    // Returns the MARC attr with the same type and value as the applied
    // order identifier (which is a local attr)
    selectedIdent(li: IdlObject): number {
        const ident = this.liService.getOrderIdent(li);
        if (!ident) { return null; }

        const attr = this.identOptions(li).filter(
            (entry: ComboboxEntry) => entry.label === ident.attr_value())[0];
        return attr ? attr.id : null;
    }

    currentIdent(li: IdlObject): IdlObject {
        return this.liService.getOrderIdent(li);
    }

    orderIdentChanged(li: IdlObject, entry: ComboboxEntry) {
        if (entry === null) { return; }

        this.liService.changeOrderIdent(
            li, entry.id, this.orderIdentTypes[li.id()], entry.label
        ).subscribe(freshLi => this.ingestOneLi(freshLi, true));
    }

    canEditIdent(li: IdlObject): boolean {
        return DELETABLE_STATES.includes(li.state());
    }

    addBriefRecord() {
    }

    selectedIds(): number[] {
        return Object.keys(this.selected)
            .filter(id => this.selected[id] === true)
            .map(id => Number(id));
    }


    // After a page of LI's are loaded, see if the batch-select checkbox
    // needs to be on or off.
    setBatchSelect() {
        let on = true;
        const ids = this.selectedIds();
        this.pageOfLineitems.forEach(li => {
            if (!ids.includes(li.id())) { on = false; }
        });

        this.batchSelectPage = on;

        on = true;

        this.lineitemIds.forEach(id => {
            if (!this.selected[id]) { on = false; }
        });

        this.batchSelectAll = on;
    }

    toggleSelectAll(allItems: boolean) {

        if (allItems) {
            this.lineitemIds.forEach(
                id => this.selected[id] = this.batchSelectAll);

            this.batchSelectPage = this.batchSelectAll;

        } else {

            this.pageOfLineitems.forEach(
                li => this.selected[li.id()] = this.batchSelectPage);

            if (!this.batchSelectPage) {
                // When deselecting items in the page, we're no longer
                // selecting all items.
                this.batchSelectAll = false;
            }
        }
    }

    applyBatchNote() {
        const ids = this.selectedIds();
        if (ids.length === 0 || !this.batchNote) { return; }

        this.liService.applyBatchNote(ids, this.batchNote, this.noteIsPublic)
            .then(resp => this.load());
    }

    liPriceIsValid(li: IdlObject): boolean {
        const price = li.estimated_unit_price();
        if (price === null || price === undefined || price === '') {
            return true;
        }
        return !Number.isNaN(Number(price)) && Number(price) >= 0;
    }

    liPriceChange(li: IdlObject) {
        if (this.liPriceIsValid(li)) {
            const price = Number(li.estimated_unit_price()).toFixed(2);
            this.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem.price.set',
                this.auth.token(), li.id(), price
            ).subscribe(resp => {
                // update local copy
                li.estimated_unit_price(price);
                this.liService.activateStateChange.emit(li.id());
            });
        }
    }

    invoiceEntryInvItemCountIsValid(li: IdlObject): boolean {
        const entry = this.invoiceEntryMap[li.id()];
        if (entry) {
            const inv_item_count = entry.inv_item_count();
            if (inv_item_count === null || inv_item_count === undefined || inv_item_count === '') {
                return true;
            }
            return Number.isInteger(inv_item_count) && Number(inv_item_count) >= 0;
        } else {
            console.warn('LineitemListComponent, input widget missing backing object??',li);
            return false;
        }
    }

    invoiceEntryPhyItemCountIsValid(li: IdlObject): boolean {
        const entry = this.invoiceEntryMap[li.id()];
        if (entry) {
            const phys_item_count = entry.phys_item_count();
            if (phys_item_count === null || phys_item_count === undefined || phys_item_count === '') {
                return true;
            }
            return Number.isInteger(phys_item_count) && Number(phys_item_count) >= 0;
        } else {
            console.warn('LineitemListComponent, input widget missing backing object??',li);
            return false;
        }
    }

    invoiceEntryCostBilledIsValid(li: IdlObject): boolean {
        const entry = this.invoiceEntryMap[li.id()];
        if (entry) {
            const cost_billed = entry.cost_billed();
            if (cost_billed === null || cost_billed === undefined || cost_billed === '') {
                return true;
            }
            return !isNaN(Number(cost_billed)) && Number(cost_billed) >= 0;
        } else {
            console.warn('LineitemListComponent, input widget missing backing object??',li);
            return false;
        }
    }

    invoiceEntryAmountPaidIsValid(li: IdlObject): boolean {
        const entry = this.invoiceEntryMap[li.id()];
        if (entry) {
            const amount_paid = entry.amount_paid();
            if (amount_paid === null || amount_paid === undefined || amount_paid === '') {
                return true;
            }
            return !isNaN(Number(amount_paid)) && Number(amount_paid) >= 0;
        } else {
            console.warn('LineitemListComponent, input widget missing backing object??',li);
            return false;
        }
    }

    invoiceEntryChangeRollback(entry: IdlObject, liId: number, fieldName: string, value: any) {
        this.zone.run(() => {

            console.warn('LineitemListComponent, invoiceEntryChange, rollback', liId, fieldName, value);
            entry[fieldName](value);
            entry.ischanged(false);
            // redundancies, trying to get change detection to work
            this.invoiceEntryMap[liId][fieldName](value);
            this.invoiceEntryMap[liId].ischanged(false);
            this.changeDetector.detectChanges();

        });
    }

    async handleInvoiceEntryMoney(
        entry: IdlObject,
        oldValue: any,
        newValue: any,
        funds: number[],
        li: IdlObject,
        options = {}
    ): Promise<boolean> /* false is asking the caller to rollback the model */ {
        console.debug('LineitemListComponent, handleInvoiceEntryMoney(entry,oldValue,newValue,funds,li)',
            entry,oldValue,newValue,funds,li);

        const extra_and_emit = () => {
            // any extra behavior? not for the new generic version of this method
            return true;
        };

        const difference = (Number(newValue)||0) - (Number(oldValue)||0);
        if ( funds.length && options['checkFundThresholds'] && difference > 0 ) {
            /* this may encumber more funds, so test thresholds */
            let results: any;
            try {
                results = await firstValueFrom( this.invoiceService.checkAmountAgainstFunds(funds, difference) );
                console.debug('LineitemListComponent, handleInvoiceEntryMoney, funds check', results);
            } catch(E) {
                console.error('LineitemListComponent, handleInvoiceEntryMoney, 1: error checking amount against fund(s)', E);
                return false;
            }
            try {
                const evt = this.evt.parse(results);
                if (!evt) {
                    let warn_triggered = false;
                    let stop_triggered = false;
                    let can_override_stop_for_all_funds_involved = true;
                    const stop_funds = [];
                    const warn_funds = [];
                    for (const {fundId, stop, warn} of results) {
                        const fund = await this.liService.getFund(fundId);
                        if (stop) {
                            stop_triggered = true;
                            stop_funds.push(fund);
                            if (!this.permissions.ACQ_ALLOW_OVERSPEND.includes(fund.org())) {
                                can_override_stop_for_all_funds_involved = false;
                            }
                        } else if (warn) {
                            warn_triggered = true;
                            warn_funds.push(fund);
                        }
                    }
                    if (stop_triggered) {
                        console.warn('LineitemListComponent, stop /* ACQ_FUND_EXCEEDS_STOP_PERCENT */');
                        if (can_override_stop_for_all_funds_involved) {
                            // this.stopPercentConfirmDialog.funds = stop_funds;
                            const response = await firstValueFrom(
                                this.stopPercentConfirmDialog.open()
                            );
                            return response ? extra_and_emit() : false;
                        } else {
                            // this.stopPercentAlertDialog.funds = stop_funds;
                            await lastValueFrom(
                                this.stopPercentAlertDialog.open().pipe(defaultIfEmpty(null))
                            );
                            return false;
                        }
                    } else if (warn_triggered) {
                        console.warn('LineitemListComponent, warn /* ACQ_FUND_EXCEEDS_WARN_PERCENT */');
                        // this.warnPercentConfirmDialog.funds = warn_funds;
                        const response = await firstValueFrom(
                            this.warnPercentConfirmDialog.open()
                        );
                        return response ? extra_and_emit() : false;
                    }
                    return true;
                } else {
                    console.error('LineitemListComponent, handleInvoiceEntryMoney, 2: error checking amount against fund', evt);
                    return false;
                }
            } catch(E) {
                console.error('LineitemListComponent, handleInvoiceEntryMoney, 3: error checking amount against fund', E);
                return false;
            }
        } else {
            /* but no reason not to let someone reduce a value */
            return extra_and_emit();
        }
    }

    async handleInvoiceEntryPhysItemCount(
        entry: IdlObject,
        oldValue: any,
        newValue: any,
        funds: number[],
        li: IdlObject
    ): Promise<boolean> /* false is asking the caller to rollback the model */ {
        console.debug('LineitemListComponent, handleInvoiceEntryPhysItemCount(entry,oldValue,newValue,funds,li)',
            entry,oldValue,newValue,funds,li);
        const extra = Number(entry.phys_item_count())
            - Number(li.item_count())
            - Number(li.order_summary().invoice_count());
        console.debug('LineitemListComponent, handleInvoiceEntryPhysItemCount, Extra copies being received', extra);
        this.confirmExtraItemsDialog.extra_count = extra;
        this.confirmExtraItemsDialog.owners = this.org.ancestors(this.auth.user().ws_ou(), true);
        if (extra > 0) {
            const fund = await lastValueFrom( this.confirmExtraItemsDialog.open() );
            if (!fund) {
                return false; // rollback
            } else {
                console.debug('LineitemListComponent, handleInvoiceEntryPhysItemCount: creating acqlids for extra items with fund =', fund);
                const liDetails = li.lineitem_details() || [];
                for (let i = 0; i < extra; i++) {
                    const lid = this.idl.create('acqlid');
                    lid.isnew(true);
                    lid.lineitem(li.id());
                    lid.fund(fund.id);
                    lid.recv_time('now');
                    liDetails.push(lid);
                }
                li.lineitem_details( liDetails );
                try {
                    const result = await lastValueFrom(this.liService.updateLiDetails(li, true, false));
                    console.debug('LineitemListComponent, handleInvoiceEntryPhysItemCount, updateLiDetails',
                        result);
                    return true;
                } catch(E) {
                    console.error('LineitemListComponent, handleInvoiceEntryPhysItemCount, updateLiDetails',
                        E);
                    window.alert($localize`Error updating line item with copies.`);
                    return false;
                }
            }
        } else {
            return true;
        }
    }

    handleInvoiceEntryChange(li: IdlObject, newValue: any, fieldName: string) {
        console.debug('LineitemListComponent, handleInvoiceEntryChange(li,newValue,fieldName)', li, newValue, fieldName);

        const extra_and_emit = () => {
            this.invoiceService.updateInvoiceEntry(entry);
            console.debug('LineitemListComponent, extra_and_emit', this.invoiceService.currentInvoice);
            this.invoiceService.changeNotify();
        };

        const entry = this.invoiceEntryMap[li.id()];

        const funds: number[] = Array.from(
            new Set((li.lineitem_details()||[]).map( (lid: IdlObject) => lid.fund() ))); // dedupe
        console.debug('LineitemListComponent, handleInvoiceEntryChange, funds', funds, li.lineitem_details());

        if (entry) {

            const oldValue = entry[fieldName]();
            entry.ischanged(true);
            entry[fieldName](newValue);

            if (fieldName == 'cost_billed') {
                // false as the last parameter says don't check fund thresholds
                this.handleInvoiceEntryMoney(entry, oldValue, newValue, funds, li, {checkFundThresholds: false}).then(
                    (keep: boolean) => {
                        if (keep) {
                            if (entry.amount_paid() === undefined || entry.amount_paid() === null || entry.amount_paid() === 0 || entry.amount_paid() === '') {
                                this.handleInvoiceEntryChange(li, entry.cost_billed(), 'amount_paid');
                            }
                            extra_and_emit();
                        } else {
                            this.invoiceEntryChangeRollback(entry, li.id(),'cost_billed',oldValue);
                        }
                    }
                );
                return;
            }
            if (fieldName == 'amount_paid') {
                // true as the last parameter says check fund thresholds
                this.handleInvoiceEntryMoney(entry, oldValue, newValue, funds, li, {checkFundThresholds: true}).then(
                    (keep: boolean) => {
                        if (keep) {
                            extra_and_emit();
                        } else {
                            this.invoiceEntryChangeRollback(entry, li.id(),'amount_paid',oldValue);
                        }
                    }
                );
                return;
            }

            if (fieldName == 'phys_item_count') {
                this.handleInvoiceEntryPhysItemCount(entry, oldValue, newValue, funds, li).then(
                    (keep: boolean) => {
                        if (keep) {
                            extra_and_emit();
                        } else {
                            this.invoiceEntryChangeRollback(entry, li.id(),'phys_item_count',oldValue);
                        }
                    }
                );
                return;
            }

            // everything else
            extra_and_emit();
        } else {
            console.warn('LineitemListComponent, invoiceEntryChange but backing invoice entry is missing??',entry);
        }
    }

    toggleShowNotes(liId: number) {
        this.showNotesFor = this.showNotesFor === liId ? null : liId;
        this.expandLineitem[liId] = false;
    }

    toggleShowExpand(liId: number) {
        this.showNotesFor = null;
        this.expandLineitem[liId] = !this.expandLineitem[liId];
    }

    toggleExpandAll() {
        this.showNotesFor = null;
        this.expandAll = !this.expandAll;
        if (this.expandAll) {
            this.pageOfLineitems.forEach(li => this.expandLineitem[li.id()] = true);
        } else {
            this.pageOfLineitems.forEach(li => this.expandLineitem[li.id()] = false);
        }
    }

    toggleFilterSort() {
        this.showFilterSort = !this.showFilterSort;
    }

    liHasAlerts(li: IdlObject): boolean {
        return li.lineitem_notes().filter(n => n.alert_text()).length > 0;
    }

    deleteLineitems() {
        const ids = Object.keys(this.selected).filter(id => this.selected[id]);

        this.deleteLineitemsDialog.ids = ids.map(i => Number(i));
        this.deleteLineitemsDialog.open().subscribe(doIt => {
            if (!doIt) { return; }

            const method = this.poId ?
                'open-ils.acq.purchase_order.lineitem.delete' :
                'open-ils.acq.picklist.lineitem.delete';

            from(ids)
                .pipe(concatMap(id =>
                    this.net.request('open-ils.acq', method, this.auth.token(), id)
                // TODO: cap parallelism
                ))
                .pipe(concatMap(_ => of(true) ))
                .subscribe(r => {}, (err: unknown) => {}, () => {
                    ids.forEach(id => {
                        delete this.liService.liCache[id];
                        delete this.selected[id];
                    });
                    this.batchSelectAll = false;
                    this.load();
                });
        });
    }

    addCopiesToLineitems() {
        const ids = Object.keys(this.selected).filter(id => this.selected[id]);

        this.addCopiesDialog.ids = ids.map(i => Number(i));
        this.addCopiesDialog.open({size: 'xl'}).subscribe(templateLineitem => {
            if (!templateLineitem) { return; }

            const lids = [];
            ids.forEach(li_id => {
                templateLineitem.lineitem_details().forEach(lid => {
                    const c = this.idl.clone(lid);
                    c.isnew(true);
                    c.lineitem(li_id);
                    lids.push(c);
                });
            });

            this.saving = true;
            this.progressMax = null;
            this.progressValue = 0;

            this.liService.updateLiDetailsMulti(lids).subscribe(
                struct => {
                    this.progressMax = struct.total;
                    this.progressValue++;
                },
                (err: unknown) => {},
                () => {
                    // Remove the modified LI's from the cache so we are
                    // forced to re-fetch them.
                    ids.forEach(id => delete this.liService.liCache[id]);
                    this.saving = false;
                    this.loadPageOfLis(false);
                    this.liService.activateStateChange.emit(Number(ids[0]));
                }
            );

        });
    }

    openBibFinder(liId: number) {
        this.bibFinderDialog.liId = liId;
        this.bibFinderDialog.open({size: 'xl'}).subscribe(bibId => {
            if (!bibId) { return; }

            const lis: IdlObject[] = [];
            this.liService.getFleshedLineitems([liId], { fromCache: true }).subscribe(
                liStruct => {
                    liStruct.lineitem.eg_bib_id(bibId);
                    liStruct.lineitem.attributes([]);
                    lis.push(liStruct.lineitem);
                },
                (err: unknown) => { },
                () => {
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.update',
                        this.auth.token(), lis
                    ).toPromise().then(resp => this.postBatchAction(resp, [liId]));
                }
            );
        });
    }

    batchUpdateCopiesOnLineitems() {
        const ids = Object.keys(this.selected).filter(id => this.selected[id]);

        this.batchUpdateCopiesDialog.ids = ids.map(i => Number(i));
        this.batchUpdateCopiesDialog.activated_po = this.isActivatedPo();
        
        this.batchUpdateCopiesDialog.open({size: 'xl'}).subscribe(batchChanges => {
            if (!batchChanges) { return; }

            this.saving = true;
            this.progressMax = ids.length;
            this.progressValue = 0;

            this.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem.batch_update',
                this.auth.token(), { lineitems: ids },
                batchChanges, batchChanges._dist_formula
            ).subscribe(
                response => {
                    const evt = this.evt.parse(response);
                    if (!evt) {
                        delete this.liService.liCache[response];
                        this.progressValue++;
                    }
                },
                (err: unknown) => {},
                () => {
                    this.saving = false;
                    this.loadPageOfLis(false);
                    this.liService.activateStateChange.emit(Number(ids[0]));
                }
            );
        });
    }

    exportSingleAttributeList() {
        const ids = Object.keys(this.selected).filter(id => this.selected[id]).map(i => Number(i));
        this.exportAttributesDialog.ids = ids;
        this.exportAttributesDialog.open().subscribe(attr => {
            if (!attr) { return; }

            this.liService.doExportSingleAttributeList(ids, attr);
        });
    }

    markSelectorReady(rows: IdlObject[]) {
        const ids = this.selectedIds().map(i => Number(i));
        if (ids.length === 0) { return; }

        const lis: IdlObject[] = [];
        this.liService.getFleshedLineitems(ids, { fromCache: true }).subscribe(
            liStruct => {
                if (liStruct.lineitem.state() === 'new') {
                    lis.push(liStruct.lineitem);
                }
            },
            (err: unknown) => {},
            () => {
                if (lis.length === 0) {
                    this.noActionableLIs.open();
                    return;
                }
                this.selectorReadyConfirmDialog.open().subscribe(doIt => {
                    if (!doIt) { return; }
                    lis.forEach(li => li.state('selector-ready'));
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.update',
                        this.auth.token(), lis
                    ).toPromise().then(resp => {
                        this.lineItemsUpdatedString.current()
                            .then(str => this.toast.success(str));
                        this.postBatchAction(resp, ids);
                    });
                });
            }
        );
    }

    markOrderReady(rows: IdlObject[]) {
        const ids = this.selectedIds().map(i => Number(i));
        if (ids.length === 0) { return; }

        const lis: IdlObject[] = [];
        this.liService.getFleshedLineitems(ids, { fromCache: true }).subscribe(
            liStruct => {
                if (liStruct.lineitem.state() === 'new' || liStruct.lineitem.state() === 'selector-ready') {
                    lis.push(liStruct.lineitem);
                }
            },
            (err: unknown) => {},
            () => {
                if (lis.length === 0) {
                    this.noActionableLIs.open();
                    return;
                }
                this.orderReadyConfirmDialog.open().subscribe(doIt => {
                    if (!doIt) { return; }
                    lis.forEach(li => li.state('order-ready'));
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.update',
                        this.auth.token(), lis
                    ).toPromise().then(resp => {
                        this.lineItemsUpdatedString.current()
                            .then(str => this.toast.success(str));
                        this.postBatchAction(resp, ids);
                    });
                });
            }
        );
    }

    liHasRealCopies(li: IdlObject): boolean {
        for (let idx = 0; idx < li.lineitem_details().length; idx++) {
            if (li.lineitem_details()[idx].eg_copy_id()) {
                return true;
            }
        }
        return false;
    }

    editHoldings(li: IdlObject) {

        const copies = li.lineitem_details()
            .filter(lid => lid.eg_copy_id()).map(lid => lid.eg_copy_id());

        if (copies.length === 0) { return; }

        this.holdings.spawnAddHoldingsUi(
            li.eg_bib_id(),
            copies.map(c => c.call_number()),
            null,
            copies.map(c => c.id())
        );
    }

    jumpToHoldings(li: IdlObject) {
        window.open('/eg2/staff/catalog/record/' + li.eg_bib_id() + '/holdings', '_blank');
    }

    async manageClaims(li: IdlObject, opts: { lidIds?: number[], insideBatch?: boolean } = {}) {
        const { lidIds = [], insideBatch = false } = opts;
        console.debug('LineitemListComponent, lidIds',lidIds);
        this.manageClaimsDialog.li = li;
        this.manageClaimsDialog.lidIds = lidIds;
        this.manageClaimsDialog.insideBatch = insideBatch;
        const result = await lastValueFrom( this.manageClaimsDialog.open().pipe(
            defaultIfEmpty({claimMade:false})
        ));
        if (result.claimMade) {
            delete this.liService.liCache[li.id()];
            if (!insideBatch || result.breakChain) {
                if (this.batchClaimMode) {
                    this.load();
                } else {
                    this.loadPageOfLis(false);
                }
            }
        }
        return result.breakChain;
    }

    async manageClaimsForLiIds(liIds: number[], lidIds: number[] = []) {
        await lastValueFrom(
            this.liService.getFleshedLineitems(liIds, { fromCache: true })
                .pipe(
                    defaultIfEmpty(null),
                    concatMap(async (liStruct) => {
                        const li = liStruct.lineitem;
                        const breakChain = await this.manageClaims(li, { lidIds: lidIds, insideBatch: liIds.length > 1 });
                        return !breakChain;
                    }),
                    takeWhile(shouldContinue => shouldContinue)
                )
        );
        this.loadPageOfLis(false);
    }

    countClaims(li: IdlObject): number {
        let total = 0;
        li.lineitem_details().forEach((lid: IdlObject) => total += lid.claims()?.length);
        return total;
    }

    countReceivableItems(li: IdlObject) : Number {
        const sum = li.order_summary();

        return sum.item_count() - (sum.cancel_count() + sum.recv_count());
    }

    receiveSelected() { /* lineitems*/
        this.markReceived(this.selectedIds());
    }

    selectedLidIds() {
        const lidIds = [];
        Object.keys(this.lineitemDetailSelectionMap).forEach( liId => {
            Object.keys(this.lineitemDetailSelectionMap[liId]).forEach( lidId => {
                if (this.lineitemDetailSelectionMap[liId][lidId]) {
                    lidIds.push(Number(lidId));
                }
            });
        });
        return lidIds;
    }

    liIdsForSelectedLids(): any[] {
        const liIds = new Set();
        Object.keys(this.lineitemDetailSelectionMap).forEach( liId => {
            Object.keys(this.lineitemDetailSelectionMap[liId]).forEach( lidId => {
                if (this.lineitemDetailSelectionMap[liId][lidId]) {
                    liIds.add(Number(liId));
                }
            });
        });
        return Array.from(liIds);
    }

    receiveSelectedLids() { /* items */
        console.debug('LineitemListComponent, receiveSelectedLids()');
        const liIds = this.liIdsForSelectedLids();
        const lidIds = this.selectedLidIds();
        this.markLidsReceived(liIds, lidIds);
    }

    unReceiveSelected() {
        this.markUnReceived(this.selectedIds());
    }

    cancelSelected() {
        const liIds = this.selectedIds();
        if (liIds.length === 0) { return; }

        this.cancelDialog.open().subscribe(reason => {
            if (!reason) { return; }

            this.net.request('open-ils.acq',
                'open-ils.acq.lineitem.cancel.batch',
                this.auth.token(), liIds, reason
            ).toPromise().then(resp => this.postBatchAction(resp, liIds));
        });
    }

    applyClaimPolicyToSelected() {
        const liIds = this.selectedIds();

        if (liIds.length === 0) { return; }

        this.claimPolicyDialog.ids = liIds.map(i => Number(i));
        this.claimPolicyDialog.open().subscribe(claimPolicy => {
            if (!claimPolicy) { return; }

            const lis: IdlObject[] = [];
            this.liService.getFleshedLineitems(liIds, { fromCache: true }).subscribe(
                liStruct => {
                    liStruct.lineitem.claim_policy(claimPolicy);
                    lis.push(liStruct.lineitem);
                },
                (err: unknown) => { },
                () => {
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.update',
                        this.auth.token(), lis
                    ).toPromise().then(resp => this.postBatchAction(resp, liIds));
                }
            );
        });
    }

    createInvoiceFromSelected() {
        const liIds = this.selectedIds();
        if (liIds.length === 0) { return; }
        console.warn('LineitemListComponent, got here');
        this.router.navigate(['/staff/acq/invoice/create'], {
            queryParams: {attach_li: liIds}
        });
    }

    linkInvoiceFromSelected() {
        const liIds = this.selectedIds();
        if (liIds.length === 0) { return; }

        this.linkInvoiceDialog.liIds = liIds.map(i => Number(i));
        this.linkInvoiceDialog.open().subscribe(invId => {
            if (!invId) { return; }

            this.router.navigate(['/staff/acq/invoice/' + invId], {
                queryParams: {attach_li: liIds}
            });
        });

    }

    markReceived(liIds: number[]) {
        console.debug('LineitemListComponent, markReceived',liIds);
        if (liIds.length === 0) { return; }

        const lis: IdlObject[] = [];
        this.liService.getFleshedLineitems(liIds, { fromCache: true }).subscribe(
            liStruct => lis.push(liStruct.lineitem),
            (err: unknown) => {},
            () => {
                this.liService.checkLiAlerts(lis, this.confirmAlertsDialog).then(ok => {
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.receive.batch',
                        this.auth.token(), liIds
                    ).toPromise().then(resp => this.postBatchAction(resp, liIds));
                }, err => {}); // avoid console errors
            }
        );
    }

    markLidsReceived(liIds: number[], lidIds: number[]) {
        console.debug('LineitemListComponent, markLidsReceived', lidIds);
        console.debug('LineitemListComponent, associated lineitems', liIds);
        if (liIds.length  === 0) { return; }
        if (lidIds.length === 0) { return; }

        const lids: IdlObject[] = [];
        const lis: IdlObject[] = [];
        this.liService.getFleshedLineitems(liIds, { fromCache: true }).subscribe(
            liStruct => lis.push(liStruct.lineitem),
            (_: unknown) => {},
            () => {
                this.liService.checkLiAlerts(lis, this.confirmAlertsDialog).then(ok => {
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem_detail.receive.batch',
                        this.auth.token(), lidIds
                    ).toPromise().then(resp => this.postBatchActionLids(resp, liIds, lidIds));
                }, _ => {}); // avoid console errors
            }
        );
    }

    markUnReceived(liIds: number[]) {
        if (liIds.length === 0) { return; }

        this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem.receive.rollback.batch',
            this.auth.token(), liIds
        ).toPromise().then(resp => this.postBatchAction(resp, liIds));
    }

    postBatchAction(response: any, liIds: number[]) {
        const evt = this.evt.parse(response);

        if (evt) {
            console.warn('LineitemListComponent, Batch operation failed', evt);
            this.batchFailure = evt;
            return;
        }

        this.batchFailure = null;

        // Remove the modified LI's from the cache so we are
        // forced to re-fetch them.
        liIds.forEach(id => delete this.liService.liCache[id]);

        this.loadPageOfLis(false);
    }

    postBatchActionLids(response: any, liIds: number[], lidIds: number[]) {
        const evt = this.evt.parse(response);

        if (evt) {
            console.warn('LineitemListComponent, Batch operation failed', evt);
            this.batchFailure = evt;
            return;
        }

        this.batchFailure = null;

        // Remove the modified LI's from the cache so we are
        // forced to re-fetch them.
        liIds.forEach(id => delete this.liService.liCache[id]);

        this.loadPageOfLis(false);
    }

    createPo(fromAll?: boolean) {
        this.router.navigate(['/staff/acq/po/create'], {
            queryParams: {li: fromAll ? this.lineitemIds : this.selectedIds()}
        });
    }

    // order was activated as some point in past
    isActivatedPo(): boolean {
        if (this.picklistId) {
            return false; // not an order
        } else if (this.invoice()) {
            return true; // has to be activated to be invoiced
        } else {
            if (this.po()) {
                this.poWasActivated = this.po().order_date() ? true : false;
            }
            return this.poWasActivated;
        }
    }

    isPendingPo(): boolean {
        if (this.picklistId || !this.po()) {
            return false;
        } else {
            return this.po().order_date() ? false : true;
        }
    }

    // For PO's, lineitems can only be deleted if they are pending order.
    canDeleteLis(): boolean {
        const li = this.pageOfLineitems[0];
        return Boolean(this.picklistId) || (
            Boolean(li) &&
            DELETABLE_STATES.includes(li.state()) &&
            Boolean(this.poId)
        );
    }

    lineitemDisposition(li: IdlObject): LINEITEM_DISPOSITION {
        return this.liService.lineitemDisposition(li);
    }

    disabledViaInvoice() {
        return this.invoice() && !!this.invoice().close_date();
    }

    price_per_copy(li: IdlObject): number {
        const entry = this.invoiceEntryMap[li.id()];
        if (!entry) {
            console.error('price_per_copy called with no backing invoice entry',li);
            return 0;
        }
        // return $entry->amount_paid if $U->is_true($entry->billed_per_item);
        if (entry.billed_per_item()) {
            return entry.amount_paid();
        }
        // return 0 if $entry->phys_item_count == 0;
        if (entry.phys_item_count() === 0) {
            return 0;
        }
        // return $entry->amount_paid / $entry->phys_item_count;
        return entry.amount_paid() / entry.phys_item_count();
    }

    reAndDeTachLiFromInvoice(li: IdlObject, isdeleted: boolean) {
        console.warn('LineitemListComponent, detachLiFromInvoice',li);
        const entry = this.invoiceEntryMap[li.id()];
        if (!entry) {
            console.error('LineitemListComponent, detachLiFromInvoice: found no backing invoice entry');
            return;
        }
        entry.isdeleted(isdeleted);
        const entries = this.invoice().entries().map((e: IdlObject) => {
            if (e.id() !== entry.id()) {
                return e;
            } else {
                // in-place swap of original entry with the one instantiated in this component
                return entry;
            }
        });
        this.invoice().entries( entries );
        this.invoiceService.changeNotify();
    }

    adjustNumberReceived(liId: number) {
        const count = this.getLidCount(liId);
        this.lineitemDetailCountMap[liId] = count;
    }

    getLidCount(lineitemId: number): number {
        let count = 0;
        const lineitemDetailMap = this.lineitemDetailSelectionMap[lineitemId];

        if (lineitemDetailMap) {
            for (const detailId in lineitemDetailMap) {
                if (lineitemDetailMap[detailId]) {
                    count++;
                }
            }
        }
        return count;
    }

    // Select All / De-select All
    batchLidSelectionToggle(li: IdlObject, event: any) {
        // console.log('LineitemListComponent, batchLidSelectionToggle()', event.target.checked, li);
        for (const lid of li.lineitem_details()) {
            this.lineitemDetailSelectionMap[li.id()][lid.id()] = event.target.checked;
        }
        this.adjustNumberReceived(li.id());
    }

    adjustSelectedLids(liId: number, newCount: number) {
        const sortedDetailIds = Object.keys(this.lineitemDetailSelectionMap[liId] || {}).sort();
        const maxCount = sortedDetailIds.length;
        const selectedDetailIds = sortedDetailIds.filter(id => this.lineitemDetailSelectionMap[liId][id]);
        const selectedCount = selectedDetailIds.length;
        const unselectedDetailIds = sortedDetailIds.filter(id => !this.lineitemDetailSelectionMap[liId][id]);

        if (newCount > maxCount) {
            newCount = maxCount;
            this.lineitemDetailCountMap[liId] = maxCount;
        }
        if (newCount < 0) {
            newCount = 0;
            this.lineitemDetailCountMap[liId] = 0;
        }

        let eligibleDetailIds: string[];
        if (newCount > selectedCount) {
            eligibleDetailIds = unselectedDetailIds;
        } else if (newCount < selectedCount) {
            eligibleDetailIds = selectedDetailIds;
        } else {
            eligibleDetailIds = [];
        }

        let numberToModify = Math.abs(newCount - selectedCount);
        if (numberToModify > eligibleDetailIds.length) {
            numberToModify = eligibleDetailIds.length;
        }

        for (let i = 0; i < numberToModify; i++) {
            this.lineitemDetailSelectionMap[liId][eligibleDetailIds[i]] = (newCount > selectedCount);
        }
    }

    ngOnChanges(changes: SimpleChanges) {
        console.debug('LineitemListComponent, change noticed', changes);
        if (changes.lids) {
            this.load();
        }
    }

    removeChangeHandlers(li: IdlObject) {
        console.debug('LineitemListComponent, removeChangeHandlers', li);
        if (this.lineItemObservables[li.id()]) {
            Object.values(this.lineItemObservables[li.id()]).forEach(subject => subject.complete());
            delete this.lineItemObservables[li.id()];
        }
    }

    applyChangeHandlers(li: IdlObject) {
        console.debug('LineitemListComponent, applyChangeHandlers', li);
        const changeHandlers = ['cost_billed', 'amount_paid', 'inv_item_count', 'phys_item_count'];

        this.lineItemObservables[li.id()] = {};
        changeHandlers.forEach(fieldName => {
            // create new subject for each field for a given a line item
            this.lineItemObservables[li.id()][fieldName] = new Subject<{ li: any, newValue: any }>();

            // create subscription for each field
            this.lineItemObservables[li.id()][fieldName].pipe(
                debounceTime(1000), // milliseconds
                takeUntil(this.destroy$)
            ).subscribe(({ li, newValue }) => {
                this.handleInvoiceEntryChange(li, newValue, fieldName);
            });
        });
    }

}

