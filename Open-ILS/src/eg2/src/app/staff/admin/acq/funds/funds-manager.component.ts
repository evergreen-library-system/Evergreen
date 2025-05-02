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
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {NetService} from '@eg/core/net.service';
import {StringComponent} from '@eg/share/string/string.component';
import {FundDetailsDialogComponent} from './fund-details-dialog.component';
import {FundRolloverDialogComponent} from './fund-rollover-dialog.component';

@Component({
    selector: 'eg-funds-manager',
    templateUrl: './funds-manager.component.html'
})

export class FundsManagerComponent extends AdminPageComponent implements OnInit, AfterViewInit {
    idlClass = 'acqf';
    classLabel: string;

    @Input() startId: number;

    @ViewChild('fundDetailsDialog', { static: false }) fundDetailsDialog: FundDetailsDialogComponent;
    @ViewChild('fundRolloverDialog', { static: false }) fundRolloverDialog: FundRolloverDialogComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;

    cellTextGenerator: GridCellTextGenerator;
    canRollover = false;

    constructor(
        route: ActivatedRoute,
        ngLocation: Location,
        format: FormatService,
        idl: IdlService,
        org: OrgService,
        auth: AuthService,
        pcrud: PcrudService,
        perm: PermService,
        private perm2: PermService, // need copy because perm is private to base
        // component
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
        this.checkRolloverPerms();
        this.fieldOrder = 'name,code,year,org,active,currency_type,balance_stop_percentage,balance_warning_percentage,propagate,rollover';
        this.fieldOptions = {
            year: {
                min: new Date().getFullYear() - 10,
                max: new Date().getFullYear() + 10
            }
        };
        this.defaultNewRecord = this.idl.create('acqf');
        this.defaultNewRecord.active(true);
        this.defaultNewRecord.org(this.auth.user().ws_ou());

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
                flesh_fields: {
                    acqf: [
                        'spent_balance',
                        'combined_balance',
                        'spent_total',
                        'encumbrance_total',
                        'debit_total',
                        'allocation_total'
                    ]
                }
            };
            const reqOps = {
                fleshSelectors: true,
            };

            if (!this.contextOrg && !Object.keys(this.dataSource.filters).length) {
                // No org filter -- fetch all rows
                return this.pcrud.retrieveAll(
                    this.idlClass, searchOps, reqOps);
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
                this.idlClass, search, searchOps, reqOps);
        };

        super.ngOnInit();

        this.classLabel = this.idlClassDef.label;
        this.includeOrgDescendants = true;
    }

    ngAfterViewInit() {
        if (this.startId) {
            this.pcrud.retrieve('acqf', this.startId).subscribe(
                acqf => this.openFundDetailsDialog([acqf]),
                (err: unknown) => {},
                () => this.startId = null
            );
        }
    }

    checkRolloverPerms() {
        this.canRollover = false;

        this.perm2.hasWorkPermAt(['ADMIN_FUND_ROLLOVER'], true).then(permMap => {
            Object.keys(permMap).forEach(key => {
                if (permMap[key].length > 0) {
                    this.canRollover = true;
                }
            });
        });
    }

    openFundDetailsDialog(rows: IdlObject[]) {
        if (rows.length > 0) {
            this.fundDetailsDialog.fundId = rows[0].id();
            this.fundDetailsDialog.open({size: 'xl'}).subscribe(
                result => this.grid.reload(),
                (error: unknown) => this.grid.reload(),
                () => this.grid.reload()
            );
        }
    }

    getDefaultYear(): string {
        return new Date().getFullYear().toString();
    }

    doRollover() {
        this.fundRolloverDialog.contextOrgId = this.searchOrgs.primaryOrgId;
        this.fundRolloverDialog.open({size: 'lg'}).subscribe(
            ok => {},
            (err: unknown) => {},
            () => this.grid.reload()
        );
    }
}
