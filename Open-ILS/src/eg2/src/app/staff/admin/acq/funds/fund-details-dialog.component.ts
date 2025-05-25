import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {FormatService} from '@eg/core/format.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StoreService} from '@eg/core/store.service';
import {OrgService} from '@eg/core/org.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {FundTransferDialogComponent} from './fund-transfer-dialog.component';
import {mergeMap, Observable, of} from 'rxjs';

@Component({
    selector: 'eg-fund-details-dialog',
    templateUrl: './fund-details-dialog.component.html'
})

export class FundDetailsDialogComponent
    extends DialogComponent implements OnInit {

    @Input() fundId: number;
    fund: IdlObject;
    idlDef: any;
    fieldOrder: any;
    acqfaDataSource: GridDataSource;
    acqftrDataSource: GridDataSource;
    acqfdebDataSource: GridDataSource;

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('transferDialog', { static: false }) transferDialog: FundTransferDialogComponent;
    @ViewChild('allocateToFundDialog', { static: true }) allocateToFundDialog: FmRecordEditorComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;

    activeTab = 'summary';
    defaultTabType = 'summary';
    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private store: StoreService,
        private org: OrgService,
        private format: FormatService,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {

        this.defaultTabType =
            this.store.getLocalItem('eg.acq.fund_details.default_tab') || 'summary';
        this.activeTab = this.defaultTabType;

        this.fund = null;
        this.onOpen$.subscribe(() => {
            this.activeTab = this.defaultTabType;
            this._initRecord();
        });
        this.idlDef = this.idl.classes['acqf'];
        this.fieldOrder = 'name,code,year,org,active,currency_type,balance_stop_percentage,balance_warning_percentage,propagate,rollover';

        this.cellTextGenerator = {
            src_fund: row =>
                row.src_fund().code() + ' (' +
                row.src_fund().year() + ') (' +
                this.getOrgShortname(row.src_fund().org()) + ')',
            dest_fund: row =>
                row.dest_fund().code() + ' (' +
                row.dest_fund().year() + ') (' +
                this.getOrgShortname(row.dest_fund().org()) + ')',
            funding_source: row =>
                row.funding_source().code() + ' (' +
                    this.getOrgShortname(row.funding_source().owner()) + ')',
            funding_source_credit: row =>
                row.funding_source_credit().funding_source().code() + ' (' +
                    this.getOrgShortname(row.funding_source_credit().funding_source().owner()) + ')',
            li: row => row.li_id,
            po: row => row.po_name,
            invoice: row => row.vendor_invoice_id
        };
    }

    private _initRecord() {
        this.fund = null;
        this.acqfaDataSource = this._getDataSource('acqfa', 'create_time ASC');
        this.acqftrDataSource = this._getDataSource('acqftr', 'transfer_time ASC');
        this.acqfdebDataSource = this._getDataSource('acqfdeb', 'create_time ASC');
        this.pcrud.retrieve('acqf', this.fundId, {
            flesh: 1,
            flesh_fields: {
                acqf: [
                    'spent_balance',
                    'combined_balance',
                    'spent_total',
                    'encumbrance_total',
                    'debit_total',
                    'allocation_total',
                    'org',
                    'currency_type'
                ]
            }
        }).subscribe(res => this.fund = res);
    }

    _getDataSource(idlClass: string, sortField: string): GridDataSource {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[idlClass] = sort[0].name + ' ' + sort[0].dir;
            } else if (sortField) {
                // Default sort field
                orderBy[idlClass] = sortField;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy,
            };
            const reqOps = {
                fleshSelectors: true,
            };

            const search: any = new Array();
            if (idlClass === 'acqfa') {
                search.push({ fund: this.fundId });
            } else if (idlClass === 'acqftr') {
                search.push({
                    '-or': [
                        { src_fund: this.fundId },
                        { dest_fund: this.fundId }
                    ]
                });
                searchOps['flesh'] = 2;
                searchOps['flesh_fields'] = {
                    'acqftr': ['funding_source_credit'],
                    'acqfscred': ['funding_source']
                };
            } else if (idlClass === 'acqfdeb') {
                search.push({ fund: this.fundId });
                searchOps['flesh'] = 3;
                searchOps['flesh_fields'] = {
                    'acqfdeb': ['invoice_entry', 'invoice_items', 'po_items', 'lineitem_details'],
                    'acqie': ['invoice', 'purchase_order', 'lineitem'],
                    'acqii': ['invoice'],
                    'acqpoi': ['purchase_order'],
                    'acqlid': ['lineitem'],
                    'jub': ['purchase_order']
                };
            }

            Object.keys(gridSource.filters).forEach(key => {
                Object.keys(gridSource.filters[key]).forEach(key2 => {
                    search.push(gridSource.filters[key][key2]);
                });
            });

            return this.pcrud.search(idlClass, search, searchOps, reqOps)
                .pipe(mergeMap((row) => this.doExtraFleshing(row)));
        };

        return gridSource;
    }

    doExtraFleshing(row: IdlObject): Observable<IdlObject> {
        if (row.classname === 'acqfdeb') {
            row['vendor_invoice_id'] = null;
            row['invoice_id'] = null;
            row['po_id'] = null;
            row['po_name'] = null;
            row['li_id'] = null;
            // TODO need to verify this, but we may be able to get away with
            //      the assumption that a given fund debit never has more than
            //      one line item, purchase order, or invoice associated with it.
            if (row.invoice_entry()) {
                if (row.invoice_entry().invoice()) {
                    row['invoice_id'] = row.invoice_entry().invoice().id();
                    row['vendor_invoice_id'] = row.invoice_entry().invoice().inv_ident();
                }
                if (row.invoice_entry().purchase_order()) {
                    row['po_id'] = row.invoice_entry().purchase_order().id();
                    row['po_name'] = row.invoice_entry().purchase_order().name();
                }
                if (row.invoice_entry().lineitem()) {
                    row['li_id'] = row.invoice_entry().lineitem().id();
                }
            }
            if (row.lineitem_details() && row.lineitem_details().length) {
                if (row.lineitem_details()[0].lineitem().purchase_order()) {
                    row['li_id'] = row.lineitem_details()[0].lineitem().id();
                    row['po_id'] = row.lineitem_details()[0].lineitem().purchase_order().id();
                    row['po_name'] = row.lineitem_details()[0].lineitem().purchase_order().name();
                }
            }
            if (row.po_items() && row.po_items().length) {
                if (row.po_items()[0].purchase_order()) {
                    row['po_id'] = row.po_items()[0].purchase_order().id();
                    row['po_name'] = row.po_items()[0].purchase_order().name();
                }
            }
            if (row.invoice_items() && row.invoice_items().length) {
                if (row.invoice_items()[0].invoice()) {
                    row['invoice_id'] = row.invoice_items()[0].invoice().id();
                    row['vendor_invoice_id'] = row.invoice_items()[0].invoice().inv_ident();
                }
            }
        }
        return of(row);
    }
    formatCurrency(value: any) {
        return this.format.transform({
            value: value,
            datatype: 'money'
        });
    }

    openEditDialog() {
        this.editDialog.recordId = this.fundId;
        this.editDialog.mode = 'update';
        this.editDialog.open({size: 'lg'}).subscribe(
            { next: result => {
                this.successString.current()
                    .then(str => this.toast.success(str));
                this._initRecord();
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    }

    allocateToFund() {
        const allocation = this.idl.create('acqfa');
        allocation.fund(this.fundId);
        allocation.allocator(this.auth.user().id());
        this.allocateToFundDialog.defaultNewRecord = allocation;
        this.allocateToFundDialog.mode = 'create';

        this.allocateToFundDialog.hiddenFieldsList = ['id', 'fund', 'allocator', 'create_time'];
        this.allocateToFundDialog.fieldOrder = 'funding_source,amount,note';
        this.allocateToFundDialog.open().subscribe(
            { next: result => {
                this.successString.current()
                    .then(str => this.toast.success(str));
                this._initRecord();
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    }

    doTransfer() {
        this.transferDialog.sourceFund = this.fund;
        this.transferDialog.open().subscribe(
            ok => this._initRecord()
        );
    }

    setDefaultTab() {
        this.defaultTabType = this.activeTab;
        this.store.setLocalItem('eg.acq.fund_details.default_tab', this.activeTab);
    }

    getOrgShortname(ou: any) {
        if (typeof ou === 'object') {
            return ou.shortname();
        } else {
            return this.org.get(ou).shortname();
        }
    }

    checkNegativeAmount(val: any) {
        return Number(val) < 0;
    }
}
