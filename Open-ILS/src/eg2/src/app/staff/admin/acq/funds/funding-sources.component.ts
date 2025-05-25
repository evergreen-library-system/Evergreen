import {Component, Input, ViewChild, OnInit, AfterViewInit} from '@angular/core';
import {Location} from '@angular/common';
import {FormatService} from '@eg/core/format.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {AdminPageComponent} from '@eg/staff/share/admin-page/admin-page.component';
import {Pager} from '@eg/share/util/pager';
import {ActivatedRoute} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {NetService} from '@eg/core/net.service';
import {mergeMap, Observable, forkJoin, of} from 'rxjs';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {FundingSourceTransactionsDialogComponent} from './funding-source-transactions-dialog.component';

@Component({
    selector: 'eg-funding-sources',
    templateUrl: './funding-sources.component.html'
})

export class FundingSourcesComponent extends AdminPageComponent implements OnInit, AfterViewInit {
    idlClass = 'acqfs';
    classLabel: string;

    @Input() startId: number;

    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('fundingSourceTransactionsDialog', { static: false })
        fundingSourceTransactionsDialog: FundingSourceTransactionsDialogComponent;
    @ViewChild('applyCreditDialog', { static: true }) applyCreditDialog: FmRecordEditorComponent;
    @ViewChild('allocateToFundDialog', { static: true }) allocateToFundDialog: FmRecordEditorComponent;
    @ViewChild('alertDialog', {static: false}) private alertDialog: AlertDialogComponent;
    @ViewChild('confirmDel', { static: true }) confirmDel: ConfirmDialogComponent;

    cellTextGenerator: GridCellTextGenerator;
    notOneSelectedRow: (rows: IdlObject[]) => boolean;
    notOneSelectedActiveRow: (rows: IdlObject[]) => boolean;

    constructor(
        route: ActivatedRoute,
        ngLocation: Location,
        format: FormatService,
        idl: IdlService,
        org: OrgService,
        auth: AuthService,
        pcrud: PcrudService,
        perm: PermService,
        toast: ToastService,
        private net: NetService,
        broadcaster: BroadcastService
    ) {
        super(route, ngLocation, format, idl, org, auth, pcrud, perm, toast, broadcaster);
        this.dataSource = new GridDataSource();
    }

    ngOnInit() {
        this.cellTextGenerator = {
            name: row => row.name()
        };
        this.notOneSelectedRow = (rows: IdlObject[]) => (rows.length !== 1);
        this.notOneSelectedActiveRow = (rows: IdlObject[]) => (rows.length !== 1 || rows[0].active() !== 't');
        this.fieldOrder = 'name,code,year,org,active,currency_type,balance_stop_percentage,balance_warning_percentage,propagate,rollover';
        this.defaultNewRecord = this.idl.create('acqfs');
        this.defaultNewRecord.active(true);
        this.defaultNewRecord.owner(this.auth.user().ws_ou());

        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idlClass] = sort[0].name + ' ' + sort[0].dir;
            } else if (this.sortField) {
                // Default sort field
                orderBy[this.idlClass] = this.sortField;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy,
                flesh: 1,
                flesh_fields: {
                    acqfs: ['credits', 'allocations']
                }
            };
            const reqOps = {
                fleshSelectors: true,
            };

            if (!this.contextOrg && !Object.keys(this.dataSource.filters).length) {
                // No org filter -- fetch all rows
                return this.pcrud.retrieveAll(
                    this.idlClass, searchOps, reqOps)
                    .pipe(mergeMap((row) => this.calculateSummary(row)));
            }

            const search: any = new Array();
            const orgFilter: any = {};

            if (this.orgField && (this.searchOrgs || this.contextOrg)) {
                orgFilter[this.orgField] =
                    this.searchOrgs.orgIds || [this.contextOrg.id()];
                search.push(orgFilter);
            }

            Object.keys(this.dataSource.filters).forEach(key => {
                Object.keys(this.dataSource.filters[key]).forEach(key2 => {
                    search.push(this.dataSource.filters[key][key2]);
                });
            });

            return this.pcrud.search(
                this.idlClass, search, searchOps, reqOps)
                .pipe(mergeMap((row) => this.calculateSummary(row)));
        };

        super.ngOnInit();

        this.classLabel = this.idlClassDef.label;
        this.includeOrgDescendants = true;
    }

    ngAfterViewInit() {
        if (this.startId) {
            this.pcrud.retrieve('acqfs', this.startId).subscribe(
                { next: acqfs => this.openTransactionsDialog([acqfs], 'allocations'),
                    error: (err: unknown) => {},
                    complete: () => this.startId = null }
            );
        }
    }

    calculateSummary(row: IdlObject): Observable<IdlObject> {
        row['balance'] = 0;
        row['total_credits'] = 0;
        row['total_allocations'] = 0;

        row.credits().forEach((c) => row['total_credits'] += Number(c.amount()));
        row.allocations().forEach((a) => row['total_allocations'] += Number(a.amount()));
        row['balance'] = row['total_credits'] - row['total_allocations'];
        return of(row);
    }

    deleteSelected(rows: IdlObject[]) {
        if (rows.length > 0) {
            const id = rows[0].id();
            let can = true;
            forkJoin([
                this.pcrud.search('acqfa',      { funding_source: id }, { limit: 1 }, { atomic: true }),
                this.pcrud.search('acqfscred',  { funding_source: id }, { limit: 1 }, { atomic: true }),
            ]).subscribe(
                { next: results => {
                    results.forEach((res) => {
                        if (res.length > 0) {
                            can = false;
                        }
                    });
                }, error: (err: unknown) => {}, complete: () => {
                    if (can) {
                        // eslint-disable-next-line rxjs-x/no-nested-subscribe
                        this.confirmDel.open().subscribe(confirmed => {
                            if (!confirmed) { return; }
                            super.deleteSelected([ rows[0] ]);
                        });
                    } else {
                        this.alertDialog.open();
                    }
                } }
            );
        }
    }

    openTransactionsDialog(rows: IdlObject[], tab: string) {
        if (rows.length !== 1) { return; }
        this.fundingSourceTransactionsDialog.fundingSourceId = rows[0].id();
        this.fundingSourceTransactionsDialog.activeTab = tab;
        this.fundingSourceTransactionsDialog.open({size: 'xl'}).subscribe(
            { next: res => {}, error: (err: unknown) => {}, complete: () => this.grid.reload() }
        );
    }

    createCredit(rows: IdlObject[]) {
        if (rows.length !== 1) { return; }
        const fundingSourceId = rows[0].id();
        const credit = this.idl.create('acqfscred');
        credit.funding_source(fundingSourceId);
        this.applyCreditDialog.defaultNewRecord = credit;
        this.applyCreditDialog.mode = 'create';
        this.applyCreditDialog.hiddenFieldsList = ['id', 'funding_source'];
        this.applyCreditDialog.fieldOrder = 'amount,note,effective_date,deadline_date';
        this.applyCreditDialog.open().subscribe(
            { next: result => {
                this.successString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    }

    allocateToFund(rows: IdlObject[]) {
        if (rows.length !== 1) { return; }
        const fundingSourceId = rows[0].id();
        const allocation = this.idl.create('acqfa');
        allocation.funding_source(fundingSourceId);
        allocation.allocator(this.auth.user().id());
        this.allocateToFundDialog.defaultNewRecord = allocation;
        this.allocateToFundDialog.mode = 'create';

        this.allocateToFundDialog.hiddenFieldsList = ['id', 'funding_source', 'allocator', 'create_time'];
        this.allocateToFundDialog.fieldOrder = 'fund,amount,note';
        this.allocateToFundDialog.open().subscribe(
            { next: result => {
                this.successString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } }
        );
    }
}
