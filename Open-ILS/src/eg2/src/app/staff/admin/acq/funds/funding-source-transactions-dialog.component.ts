import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {FormatService} from '@eg/core/format.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {OrgService} from '@eg/core/org.service';

@Component({
    selector: 'eg-funding-source-transactions-dialog',
    templateUrl: './funding-source-transactions-dialog.component.html'
})

export class FundingSourceTransactionsDialogComponent
    extends DialogComponent implements OnInit {

    @Input() fundingSourceId: number;
    @Input() activeTab = 'credits';
    fundingSource: IdlObject;
    idlDef: any;
    fieldOrder: any;
    acqfaDataSource: GridDataSource;
    acqfscredDataSource: GridDataSource;
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('applyCreditDialog', { static: true }) applyCreditDialog: FmRecordEditorComponent;
    @ViewChild('allocateToFundDialog', { static: true }) allocateToFundDialog: FmRecordEditorComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private org: OrgService,
        private format: FormatService,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {
        this.cellTextGenerator = {
            fund: row => {
                return row.code() + ' (' + row.year() + ') (' +
                    this.getOrgShortname(row.org()) + ')';
            }
        };
        this.fundingSource = null;
        this.onOpen$.subscribe(() => this._initRecord());
        this.idlDef = this.idl.classes['acqfs'];
        this.fieldOrder = 'name,code,year,org,active,currency_type,balance_stop_percentage,balance_warning_percentage,propagate,rollover';
    }

    private _initRecord() {
        this.fundingSource = null;
        this.acqfaDataSource = this._getDataSource('acqfa', 'create_time DESC');
        this.acqfscredDataSource = this._getDataSource('acqfscred', 'effective_date DESC');
        this.pcrud.retrieve('acqfs', this.fundingSourceId, {}
        ).subscribe(res => this.fundingSource = res);
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
            search.push({ funding_source: this.fundingSourceId });

            Object.keys(gridSource.filters).forEach(key => {
                Object.keys(gridSource.filters[key]).forEach(key2 => {
                    search.push(gridSource.filters[key][key2]);
                });
            });

            return this.pcrud.search(
                idlClass, search, searchOps, reqOps);
        };

        return gridSource;
    }

    formatCurrency(value: any) {
        return this.format.transform({
            value: value,
            datatype: 'money'
        });
    }

    createCredit(grid: GridComponent) {
        const credit = this.idl.create('acqfscred');
        credit.funding_source(this.fundingSourceId);
        this.applyCreditDialog.defaultNewRecord = credit;
        this.applyCreditDialog.mode = 'create';
        this.applyCreditDialog.hiddenFieldsList = ['id', 'funding_source'];
        this.applyCreditDialog.fieldOrder = 'amount,note,effective_date,deadline_date';
        this.applyCreditDialog.open().subscribe(
            { next: result => {
                this.successString.current()
                    .then(str => this.toast.success(str));
                grid.reload();
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    }

    allocateToFund(grid: GridComponent) {
        const allocation = this.idl.create('acqfa');
        allocation.funding_source(this.fundingSourceId);
        allocation.allocator(this.auth.user().id());
        this.allocateToFundDialog.defaultNewRecord = allocation;
        this.allocateToFundDialog.mode = 'create';

        this.allocateToFundDialog.hiddenFieldsList = ['id', 'funding_source', 'allocator', 'create_time'];
        this.allocateToFundDialog.fieldOrder = 'fund,amount,note';
        this.allocateToFundDialog.open().subscribe(
            { next: result => {
                this.successString.current()
                    .then(str => this.toast.success(str));
                grid.reload();
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    }

    getOrgShortname(ou: any) {
        if (typeof ou === 'object') {
            return ou.shortname();
        } else {
            return this.org.get(ou).shortname();
        }
    }
}
