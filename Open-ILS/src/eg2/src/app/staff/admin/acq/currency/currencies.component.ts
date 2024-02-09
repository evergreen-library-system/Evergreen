import {Component, Input, ViewChild, OnInit} from '@angular/core';
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
import {NetService} from '@eg/core/net.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ExchangeRatesDialogComponent} from './exchange-rates-dialog.component';
import {Observable, forkJoin, of} from 'rxjs';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    templateUrl: './currencies.component.html'
})

export class CurrenciesComponent extends AdminPageComponent implements OnInit {
    idlClass = 'acqct';
    classLabel: string;

    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('exchangeRatesDialog', { static: false }) exchangeRatesDialog: ExchangeRatesDialogComponent;
    @ViewChild('alertDialog', {static: false}) private alertDialog: AlertDialogComponent;
    @ViewChild('confirmDel', { static: true }) confirmDel: ConfirmDialogComponent;

    cellTextGenerator: GridCellTextGenerator;
    notOneSelectedRow: (rows: IdlObject[]) => boolean;

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
        private net: NetService
    ) {
        super(route, ngLocation, format, idl, org, auth, pcrud, perm, toast);
        this.dataSource = new GridDataSource();
    }

    ngOnInit() {
        this.notOneSelectedRow = (rows: IdlObject[]) => (rows.length !== 1);
        this.cellTextGenerator = {
            exchange_rates: row => ''
        };
        this.fieldOrder = 'code,name';
        this.defaultNewRecord = this.idl.create('acqct');

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
                order_by: orderBy
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

    openExchangeRatesDialog(code: string) {
        this.exchangeRatesDialog.currencyCode = code;
        this.exchangeRatesDialog.open({size: 'lg'});
    }

    deleteIfPossible(rows: IdlObject[]) {
        if (rows.length > 0) {
            const code = rows[0].code();
            let can = true;
            forkJoin([
                this.pcrud.search('acqexr',  { from_currency: code }, { limit: 1 }, { atomic: true }),
                this.pcrud.search('acqexr',  { to_currency: code },   { limit: 1 }, { atomic: true }),
                this.pcrud.search('acqf',    { currency_type: code }, { limit: 1 }, { atomic: true }),
                this.pcrud.search('acqpro',  { currency_type: code }, { limit: 1 }, { atomic: true }),
                this.pcrud.search('acqfdeb', { origin_currency_type: code }, { limit: 1 }, { atomic: true }),
                this.pcrud.search('acqfs',   { currency_type: code }, { limit: 1 }, { atomic: true }),
            ]).subscribe(
                results => {
                    results.forEach((res) => {
                        if (res.length > 0) {
                            can = false;
                        }
                    });
                },
                err => {},
                () => {
                    if (can) {
                        this.confirmDel.open().subscribe(confirmed => {
                            if (!confirmed) { return; }
                            super.doDelete([ rows[0] ]);
                        });
                    } else {
                        this.alertDialog.open();
                    }
                }
            );
        }
    }

    calculateReadonlyFields(mode: string) {
        return mode === 'update' ? 'code' : '';
    }

}
