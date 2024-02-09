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
import {map, mergeMap} from 'rxjs/operators';
import {StringComponent} from '@eg/share/string/string.component';
import {DistributionFormulaEditDialogComponent} from './distribution-formula-edit-dialog.component';
import {Observable, forkJoin, of} from 'rxjs';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    templateUrl: './distribution-formulas.component.html'
})

export class DistributionFormulasComponent extends AdminPageComponent implements OnInit {
    idlClass = 'acqdf';
    classLabel: string;

    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('distributionFormulaEditDialog', { static: false }) distributionFormulaEditDialog: DistributionFormulaEditDialogComponent;
    @ViewChild('alertDialog', {static: false}) private alertDialog: AlertDialogComponent;
    @ViewChild('confirmDel', { static: true }) confirmDel: ConfirmDialogComponent;

    notOneSelectedRow: (rows: IdlObject[]) => boolean;
    cellTextGenerator: GridCellTextGenerator;

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
            name: row => row.name()
        };
        this.fieldOrder = 'name,code,year,org,active,currency_type,balance_stop_percentage,balance_warning_percentage,propagate,rollover';
        this.defaultNewRecord = this.idl.create('acqdf');
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
                    acqdf: ['entries']
                }
            };
            const reqOps = {
                fleshSelectors: true,
            };

            if (!this.contextOrg && !Object.keys(this.dataSource.filters).length) {
                // No org filter -- fetch all rows
                return this.pcrud.retrieveAll(
                    this.idlClass, searchOps, reqOps)
                        .pipe(mergeMap((row) => this.countItems(row)));
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
                    .pipe(mergeMap((row) => this.countItems(row)));
        };

        super.ngOnInit();

        this.classLabel = this.idlClassDef.label;
        this.includeOrgDescendants = true;
    }

    countItems(row: IdlObject): Observable<IdlObject> {
        row['item_count'] = 0;
        row.entries().forEach((e) => row['item_count'] += e.item_count());
        return of(row);
    }

    showEditDistributionFormulaDialog(successString: StringComponent, failString: StringComponent): Promise<any> {
        return new Promise((resolve, reject) => {
            this.distributionFormulaEditDialog.open({size: 'xl', scrollable: true}).subscribe(
                result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    resolve(result);
                },
                error => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                },
                () => this.grid.reload()
            );
        });
    }

    createNew() {
        this.distributionFormulaEditDialog.mode = 'create';
        this.showEditDistributionFormulaDialog(this.createString, this.createErrString);
    }

    editSelected(rows: IdlObject[]) {
        if (rows.length <= 0) { return; }
        this.distributionFormulaEditDialog.mode = 'update';
        this.distributionFormulaEditDialog.formulaId = rows[0].id();
        this.showEditDistributionFormulaDialog(this.successString, this.updateFailedString);
    }

    cloneSelected(rows: IdlObject[]) {
        if (rows.length <= 0) { return; }
        this.distributionFormulaEditDialog.mode = 'clone';
        this.distributionFormulaEditDialog.cloneSource = rows[0].id();
        this.showEditDistributionFormulaDialog(this.createString, this.createErrString);
    }

    deleteSelected(rows: IdlObject[]) {
        if (rows.length > 0) {
            const id = rows[0].id();
            let can = true;
            forkJoin([
                this.pcrud.search('acqdfa',  { formula: id }, { limit: 1 }, { atomic: true }),
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
}
