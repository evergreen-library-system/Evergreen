/* eslint-disable rxjs/no-nested-subscribe */
import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, of, Subscription} from 'rxjs';
import {tap, concatMap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {EgEvent, EventService} from '@eg/core/event.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {LineitemService, LINEITEM_DISPOSITION} from './lineitem.service';
import {PoService} from '../po/po.service';
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

const DELETABLE_STATES = [
    'new', 'selector-ready', 'order-ready', 'approved', 'pending-order'
];

const DEFAULT_SORT_ORDER = 'li_id_asc';
const SORT_ORDER_MAP = {
    li_id_asc:  { 'order_by': [{'class': 'jub', 'field': 'id', 'direction': 'ASC'}] },
    li_id_desc: { 'order_by': [{'class': 'jub', 'field': 'id', 'direction': 'DESC'}] },
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
export class LineitemListComponent implements OnInit {

    picklistId: number = null;
    poId: number = null;
    poWasActivated = false;
    poSubscription: Subscription;
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
    sortOrder = DEFAULT_SORT_ORDER;
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

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private store: ServerStoreService,
        private idl: IdlService,
        private toast: ToastService,
        private holdings: HoldingsService,
        private liService: LineitemService,
        private poService: PoService
    ) {}

    ngOnInit() {

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
            this.poId = +params.get('poId');
            this.recordId = +params.get('recordId');
            if (!this.firstLoad) {
                this.load();
            }
        });

        this.store.getItem('acq.lineitem.page_size').then(count => {
            // eslint-disable-next-line no-magic-numbers
            this.pager.setLimit(count || 20);
            this.store.getItem('acq.lineitem.sort_order').then(sortOrder => {
                if (sortOrder && (sortOrder in SORT_ORDER_MAP)) {
                    this.sortOrder = sortOrder;
                } else {
                    this.sortOrder = DEFAULT_SORT_ORDER;
                }
                this.load();
                this.firstLoad = false;
            });
        });

        this.poSubscription = this.poService.poRetrieved.subscribe(() => {
            this.poWasActivated = this.po().order_date() ? true : false;
        });
    }

    po(): IdlObject {
        return this.poService.currentPo;
    }

    pageSizeChange(count: number) {
        this.store.setItem('acq.lineitem.page_size', count).then(_ => {
            this.pager.setLimit(count);
            this.pager.toFirst();
            this.goToPage();
        });
    }

    sortOrderChange(sortOrder: string) {
        this.store.setItem('acq.lineitem.sort_order', sortOrder).then(_ => {
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
        this.pageOfLineitems = [];

        if (!this.loading && this.pager.limit &&
            (this.poId || this.picklistId || this.recordId)) {

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
        } else {
            Object.assign(searchTerms, { jub: [ { purchase_order: this.poId } ] });
        }

        if (this.filterApplied) {
            this._handleFiltering(searchTerms);
        }

        if (!(this.sortOrder in SORT_ORDER_MAP)) {
            this.sortOrder = DEFAULT_SORT_ORDER;
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

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem.unified_search.atomic',
            this.auth.token(),
            searchTerms, // "and" terms
            {},          // "or" terms
            null,
            opts
        ).toPromise().then(resp => {
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

    loadPageOfLis(): Promise<any> {
        this.pageOfLineitems = [];

        const ids = this.lineitemIds.slice(
            this.pager.offset, this.pager.offset + this.pager.limit)
            .filter(id => id !== undefined);

        if (ids.length === 0) { return Promise.resolve(); }

        if (this.pageOfLineitems.length === ids.length) {
            // All entries found in the cache
            return Promise.resolve();
        }

        this.pageOfLineitems = []; // reset

        return this.liService.getFleshedLineitems(
            ids, {fromCache: true, toCache: true})
            .pipe(tap(struct => {
                this.ingestOneLi(struct.lineitem);
                this.existingCopyCounts[struct.id] = struct.existing_copies;
            })).toPromise();
    }

    ingestOneLi(li: IdlObject, replace?: boolean) {
        this.liMarcAttrs[li.id()] = {};

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
                    this.loadPageOfLis();
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
                    this.loadPageOfLis();
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

    manageClaims(li: IdlObject) {
        this.manageClaimsDialog.li = li;
        this.manageClaimsDialog.open().subscribe(result => {
            if (result) {
                delete this.liService.liCache[li.id()];
                this.loadPageOfLis();
            }
        });
    }

    countClaims(li: IdlObject): number {
        let total = 0;
        li.lineitem_details().forEach(lid => total += lid.claims().length);
        return total;
    }

    receiveSelected() {
        this.markReceived(this.selectedIds());
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

        const path = '/eg/staff/acq/legacy/invoice/view?create=1&' +
                     liIds.map(x => 'attach_li=' + x.toString()).join('&');
        window.location.href = path;
    }

    linkInvoiceFromSelected() {
        const liIds = this.selectedIds();
        if (liIds.length === 0) { return; }

        this.linkInvoiceDialog.liIds = liIds.map(i => Number(i));
        this.linkInvoiceDialog.open().subscribe(invId => {
            if (!invId) { return; }

            const path = '/eg/staff/acq/legacy/invoice/view/' + invId + '?' +
                     liIds.map(x => 'attach_li=' + x.toString()).join('&');
            window.location.href = path;
        });

    }

    markReceived(liIds: number[]) {
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
            console.warn('Batch operation failed', evt);
            this.batchFailure = evt;
            return;
        }

        this.batchFailure = null;

        // Remove the modified LI's from the cache so we are
        // forced to re-fetch them.
        liIds.forEach(id => delete this.liService.liCache[id]);

        this.loadPageOfLis();
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
}

