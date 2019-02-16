import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, Observer, of} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {MarkDamagedDialogComponent
    } from '@eg/staff/share/holdings/mark-damaged-dialog.component';
import {MarkMissingDialogComponent
    } from '@eg/staff/share/holdings/mark-missing-dialog.component';
import {HoldRetargetDialogComponent
    } from '@eg/staff/share/holds/retarget-dialog.component';
import {HoldTransferDialogComponent} from './transfer-dialog.component';
import {HoldCancelDialogComponent} from './cancel-dialog.component';
import {HoldManageDialogComponent} from './manage-dialog.component';

/** Holds grid with access to detail page and other actions */

@Component({
  selector: 'eg-holds-grid',
  templateUrl: 'grid.component.html'
})
export class HoldsGridComponent implements OnInit {

    // If either are set/true, the pickup lib selector will display
    @Input() initialPickupLib: number | IdlObject;
    @Input() hidePickupLibFilter: boolean;

    // Grid persist key
    @Input() persistKey: string;

    // How to sort when no sort parameters have been applied
    // via grid controls.  This uses the eg-grid sort format:
    // [{name: fname, dir: 'asc'}, {name: fname2, dir: 'desc'}]
    @Input() defaultSort: any[];

    mode: 'list' | 'detail' | 'manage' = 'list';
    initDone = false;
    holdsCount: number;
    pickupLib: IdlObject;
    gridDataSource: GridDataSource;
    detailHold: any;
    editHolds: number[];
    transferTarget: number;
    copyStatuses: {[id: string]: IdlObject};

    @ViewChild('holdsGrid') private holdsGrid: GridComponent;
    @ViewChild('progressDialog')
        private progressDialog: ProgressDialogComponent;
    @ViewChild('transferDialog')
        private transferDialog: HoldTransferDialogComponent;
    @ViewChild('markDamagedDialog')
        private markDamagedDialog: MarkDamagedDialogComponent;
    @ViewChild('markMissingDialog')
        private markMissingDialog: MarkMissingDialogComponent;
    @ViewChild('retargetDialog')
        private retargetDialog: HoldRetargetDialogComponent;
    @ViewChild('cancelDialog')
        private cancelDialog: HoldCancelDialogComponent;
    @ViewChild('manageDialog')
        private manageDialog: HoldManageDialogComponent;

    // Bib record ID.
    _recordId: number;
    @Input() set recordId(id: number) {
        this._recordId = id;
        if (this.initDone) { // reload on update
            this.holdsGrid.reload();
        }
    }

    _userId: number;
    @Input() set userId(id: number) {
        this._userId = id;
        if (this.initDone) {
            this.holdsGrid.reload();
        }
    }

    // Include holds canceled on or after the provided date.
    // If no value is passed, canceled holds are not displayed.
    _showCanceledSince: Date;
    @Input() set showCanceledSince(show: Date) {
        this._showCanceledSince = show;
        if (this.initDone) { // reload on update
            this.holdsGrid.reload();
        }
    }

    // Include holds fulfilled on or after hte provided date.
    // If no value is passed, fulfilled holds are not displayed.
    _showFulfilledSince: Date;
    @Input() set showFulfilledSince(show: Date) {
        this._showFulfilledSince = show;
        if (this.initDone) { // reload on update
            this.holdsGrid.reload();
        }
    }

    constructor(
        private net: NetService,
        private org: OrgService,
        private auth: AuthService
    ) {
        this.gridDataSource = new GridDataSource();
        this.copyStatuses = {};
    }

    ngOnInit() {
        this.initDone = true;
        this.pickupLib = this.org.get(this.initialPickupLib);

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {

            if (this.defaultSort && sort.length === 0) {
                // Only use initial sort if sorting has not been modified
                // by the grid's own sort controls.
                sort = this.defaultSort;
            }

            // sorting not currently supported
            return this.fetchHolds(pager, sort);
        };
    }

    pickupLibChanged(org: IdlObject) {
        this.pickupLib = org;
        this.holdsGrid.reload();
    }

    applyFilters(): any {
        const filters: any = {
            is_staff_request: true,
            fulfillment_time: this._showFulfilledSince ?
                this._showFulfilledSince.toISOString() : null,
            cancel_time: this._showCanceledSince ?
                this._showCanceledSince.toISOString() : null,
        };

        if (this.pickupLib) {
            filters.pickup_lib =
                this.org.descendants(this.pickupLib, true);
        }

        if (this._recordId) {
            filters.record_id = this._recordId;
        }

        if (this._userId) {
            filters.usr_id = this._userId;
        }

        return filters;
    }

    fetchHolds(pager: Pager, sort: any[]): Observable<any> {

        // We need at least one filter.
        if (!this._recordId && !this.pickupLib && !this._userId) {
            return of([]);
        }

        const filters = this.applyFilters();

        const orderBy: any = [];
        sort.forEach(obj => {
            const subObj: any = {};
            subObj[obj.name] = {dir: obj.dir, nulls: 'last'};
            orderBy.push(subObj);
        });

        let observer: Observer<any>;
        const observable = new Observable(obs => observer = obs);

        this.progressDialog.open();
        this.progressDialog.update({value: 0, max: 1});
        let first = true;
        let loadCount = 0;
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.wide_hash.stream',
            // Pre-fetch all holds consistent with AngJS version
            this.auth.token(), filters, orderBy
            // Alternatively, fetch holds in pages.
            // this.auth.token(), filters, orderBy, pager.limit, pager.offset
        ).subscribe(
            holdData => {

                if (first) { // First response is the hold count.
                    this.holdsCount = Number(holdData);
                    first = false;

                } else { // Subsequent responses are hold data blobs

                    this.progressDialog.update(
                        {value: ++loadCount, max: this.holdsCount});

                    observer.next(holdData);
                }
            },
            err => {
                this.progressDialog.close();
                observer.error(err);
            },
            ()  => {
                this.progressDialog.close();
                observer.complete();
            }
        );

        return observable;
    }

    showDetails(rows: any[]) {
        this.showDetail(rows[0]);
    }

    showDetail(row: any) {
        if (row) {
            this.mode = 'detail';
            this.detailHold = row;
        }
    }

    showManager(rows: any[]) {
        if (rows.length) {
            this.mode = 'manage';
            this.editHolds = rows.map(r => r.id);
        }
    }

    handleModify(rowsModified: boolean) {
        this.mode = 'list';

        if (rowsModified) {
            // give the grid a chance to render then ask it to reload
            setTimeout(() => this.holdsGrid.reload());
        }
    }



    showRecentCircs(rows: any[]) {
        if (rows.length) {
            const url =
                '/eg/staff/cat/item/' + rows[0].cp_id + '/circ_list';
            window.open(url, '_blank');
        }
    }

    showPatron(rows: any[]) {
        if (rows.length) {
            const url =
                '/eg/staff/circ/patron/' + rows[0].usr_id + '/checkout';
            window.open(url, '_blank');
        }
    }

    showManageDialog(rows: any[]) {
        const holdIds = rows.map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.manageDialog.holdIds = holdIds;
            this.manageDialog.open({size: 'lg'}).then(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                },
                dismissed => {}
            );
        }
    }

    showTransferDialog(rows: any[]) {
        const holdIds = rows.map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.transferDialog.holdIds = holdIds;
            this.transferDialog.open({}).then(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                },
                dismissed => {}
            );
        }
    }

    async showMarkDamagedDialog(rows: any[]) {
        const copyIds = rows.map(r => r.cp_id).filter(id => Boolean(id));
        if (copyIds.length === 0) { return; }

        let rowsModified = false;

        const markNext = async(ids: number[]) => {
            if (ids.length === 0) {
                return Promise.resolve();
            }

            this.markDamagedDialog.copyId = ids.pop();
            this.markDamagedDialog.open({size: 'lg'}).then(
                ok => {
                    if (ok) { rowsModified = true; }
                    return markNext(ids);
                },
                dismiss => markNext(ids)
            );
        };

        await markNext(copyIds);
        if (rowsModified) {
            this.holdsGrid.reload();
        }
    }

    showMarkMissingDialog(rows: any[]) {
        const copyIds = rows.map(r => r.cp_id).filter(id => Boolean(id));
        if (copyIds.length > 0) {
            this.markMissingDialog.copyIds = copyIds;
            this.markMissingDialog.open({}).then(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                },
                dismissed => {} // avoid console errors
            );
        }
    }

    showRetargetDialog(rows: any[]) {
        const holdIds = rows.map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.retargetDialog.holdIds = holdIds;
            this.retargetDialog.open({}).then(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                },
                dismissed => {}
            );
        }
    }

    showCancelDialog(rows: any[]) {
        const holdIds = rows.map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.cancelDialog.holdIds = holdIds;
            this.cancelDialog.open({}).then(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                },
                dismissed => {}
            );
        }
    }
}


