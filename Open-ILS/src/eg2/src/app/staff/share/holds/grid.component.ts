import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, Observer, of} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {Pager} from '@eg/share/util/pager';
import {ServerStoreService} from '@eg/core/server-store.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
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
import {PrintService} from '@eg/share/print/print.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';

/** Holds grid with access to detail page and other actions */

@Component({
  selector: 'eg-holds-grid',
  templateUrl: 'grid.component.html'
})
export class HoldsGridComponent implements OnInit {

    // If either are set/true, the pickup lib selector will display
    @Input() initialPickupLib: number | IdlObject;
    @Input() hidePickupLibFilter: boolean;

    // If true, only retrieve holds with a Hopeless Date
    // and enable related Actions
    @Input() hopeless: boolean;

    // Grid persist key
    @Input() persistKey: string;

    @Input() preFetchSetting: string;

    @Input() printTemplate: string;

    // If set, all holds are fetched on grid load and sorting/paging all
    // happens in the client.  If false, sorting and paging occur on
    // the server.
    enablePreFetch: boolean;

    // How to sort when no sort parameters have been applied
    // via grid controls.  This uses the eg-grid sort format:
    // [{name: fname, dir: 'asc'}, {name: fname2, dir: 'desc'}]
    @Input() defaultSort: any[];

    // To pass through to the underlying eg-grid
    @Input() showFields: string;

    mode: 'list' | 'detail' | 'manage' = 'list';
    initDone = false;
    holdsCount: number;
    pickupLib: IdlObject;
    plCompLoaded = false;
    gridDataSource: GridDataSource;
    detailHold: any;
    editHolds: number[];
    transferTarget: number;

    @ViewChild('holdsGrid', { static: false }) private holdsGrid: GridComponent;
    @ViewChild('progressDialog', { static: true })
        private progressDialog: ProgressDialogComponent;
    @ViewChild('transferDialog', { static: true })
        private transferDialog: HoldTransferDialogComponent;
    @ViewChild('markDamagedDialog', { static: true })
        private markDamagedDialog: MarkDamagedDialogComponent;
    @ViewChild('markMissingDialog', { static: true })
        private markMissingDialog: MarkMissingDialogComponent;
    @ViewChild('retargetDialog', { static: true })
        private retargetDialog: HoldRetargetDialogComponent;
    @ViewChild('cancelDialog', { static: true })
        private cancelDialog: HoldCancelDialogComponent;
    @ViewChild('manageDialog', { static: true })
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


    cellTextGenerator: GridCellTextGenerator;

    // Include holds marked Hopeless on or after this date.
    _showHopelessAfter: Date;
    @Input() set showHopelessAfter(show: Date) {
        this._showHopelessAfter = show;
        if (this.initDone) { // reload on update
            this.holdsGrid.reload();
        }
    }

    // Include holds marked Hopeless on or before this date.
    _showHopelessBefore: Date;
    @Input() set showHopelessBefore(show: Date) {
        this._showHopelessBefore = show;
        if (this.initDone) { // reload on update
            this.holdsGrid.reload();
        }
    }

    constructor(
        private net: NetService,
        private org: OrgService,
        private store: ServerStoreService,
        private auth: AuthService,
        private printer: PrintService,
        private holdings: HoldingsService
    ) {
        this.gridDataSource = new GridDataSource();
        this.enablePreFetch = null;
    }

    ngOnInit() {
        this.initDone = true;
        this.pickupLib = this.org.get(this.initialPickupLib);

        if (this.preFetchSetting) {
            this.store.getItem(this.preFetchSetting).then(
                applied => this.enablePreFetch = Boolean(applied)
            );
        }

        if (!this.defaultSort) {
            this.defaultSort = [{name: 'request_time', dir: 'asc'}];
        }

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {

            if (!this.hidePickupLibFilter && !this.plCompLoaded) {
                // When the pickup lib selector is active, avoid any
                // data fetches until it has settled on a default value.
                // Once the final value is applied, its onchange will
                // fire and we'll be back here with plCompLoaded=true.
                return of([]);
            }

            sort = sort.length > 0 ? sort : this.defaultSort;
            return this.fetchHolds(pager, sort);
        };

        // Text-ify function for cells that use display templates.
        this.cellTextGenerator = {
            title: row => row.title,
            cp_barcode: row => (row.cp_barcode == null) ? '' : row.cp_barcode,
            ucard_barcode: row => row.ucard_barcode
        };
    }

    // Returns true after all data/settings/etc required to render the
    // grid have been fetched.
    initComplete(): boolean {
        return this.enablePreFetch !== null;
    }

    pickupLibChanged(org: IdlObject) {
        this.pickupLib = org;
        this.holdsGrid.reload();
    }

    preFetchHolds(apply: boolean) {
        this.enablePreFetch = apply;

        if (apply) {
            setTimeout(() => this.holdsGrid.reload());
        }

        if (this.preFetchSetting) {
            // fire and forget
            this.store.setItem(this.preFetchSetting, apply);
        }
    }

    applyFilters(): any {

        const filters: any = {
            is_staff_request: true,
            fulfillment_time: this._showFulfilledSince ?
                this._showFulfilledSince.toISOString() : null,
            cancel_time: this._showCanceledSince ?
                this._showCanceledSince.toISOString() : null,
        };

        if (this.hopeless) {
          filters['hopeless_holds'] = {
            'start_date' : this._showHopelessAfter
              ? (
                  // FIXME -- consistency desired, string or object
                  typeof this._showHopelessAfter === 'object'
                  ? this._showHopelessAfter.toISOString()
                  : this._showHopelessAfter
                )
              : '1970-01-01T00:00:00.000Z',
            'end_date' : this._showHopelessBefore
              ? (
                  // FIXME -- consistency desired, string or object
                  typeof this._showHopelessBefore === 'object'
                  ? this._showHopelessBefore.toISOString()
                  : this._showHopelessBefore
                )
              : (new Date()).toISOString()
          };
        }

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
        if (sort.length > 0) {
            sort.forEach(obj => {
                const subObj: any = {};
                subObj[obj.name] = {dir: obj.dir, nulls: 'last'};
                orderBy.push(subObj);
            });
        }

        const limit = this.enablePreFetch ? null : pager.limit;
        const offset = this.enablePreFetch ? 0 : pager.offset;

        let observer: Observer<any>;
        const observable = new Observable(obs => observer = obs);

        this.progressDialog.open();
        this.progressDialog.update({value: 0, max: 1});
        let first = true;
        let loadCount = 0;
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.wide_hash.stream',
            this.auth.token(), filters, orderBy, limit, offset
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

    metaRecordHoldsSelected(rows: IdlObject[]) {
        let found = false;
        rows.forEach( row => {
           if (row.hold_type === 'M') {
             found = true;
           }
        });
        return found;
    }

    nonTitleHoldsSelected(rows: IdlObject[]) {
        let found = false;
        rows.forEach( row => {
           if (row.hold_type !== 'T') {
             found = true;
           }
        });
        return found;
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
        const copyIds = Array.from(new Set( rows.map(r => r.cp_id).filter( cp_id => Boolean(cp_id)) ));
        copyIds.forEach( copyId => {
            const url =
                '/eg/staff/cat/item/' + copyId + '/circ_list';
            window.open(url, '_blank');
        });
    }

    showPatron(rows: any[]) {
        const usrIds = Array.from(new Set( rows.map(r => r.usr_id).filter( usr_id => Boolean(usr_id)) ));
        usrIds.forEach( usrId => {
            const url =
                '/eg/staff/circ/patron/' + usrId + '/checkout';
            window.open(url, '_blank');
        });
    }

    showOrder(rows: any[]) {
        // Doesn't work in Typescript currently without compiler option:
        //   const bibIds = [...new Set( rows.map(r => r.record_id) )];
        const bibIds = Array.from(
          new Set( rows.filter(r => r.hold_type !== 'M').map(r => r.record_id) ));
        bibIds.forEach( bibId => {
          const url =
              '/eg/staff/acq/legacy/lineitem/related/' + bibId + '?target=bib';
          window.open(url, '_blank');
        });
    }

    addVolume(rows: any[]) {
        const bibIds = Array.from(
          new Set( rows.filter(r => r.hold_type !== 'M').map(r => r.record_id) ));
        bibIds.forEach( bibId => {
          this.holdings.spawnAddHoldingsUi(bibId);
        });
    }

    showTitle(rows: any[]) {
        const bibIds = Array.from(new Set( rows.map(r => r.record_id) ));
        bibIds.forEach( bibId => {
          // const url = '/eg/staff/cat/catalog/record/' + bibId;
          const url = '/eg2/staff/catalog/record/' + bibId;
          window.open(url, '_blank');
        });
    }

    showManageDialog(rows: any[]) {
        const holdIds = rows.map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.manageDialog.holdIds = holdIds;
            this.manageDialog.open({size: 'lg'}).subscribe(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                }
            );
        }
    }

    showTransferDialog(rows: any[]) {
        const holdIds = rows.filter(r => r.hold_type === 'T').map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.transferDialog.holdIds = holdIds;
            this.transferDialog.open({}).subscribe(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                }
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
            return this.markDamagedDialog.open({size: 'lg'}).subscribe(
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
            this.markMissingDialog.open({}).subscribe(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                }
            );
        }
    }

    showRetargetDialog(rows: any[]) {
        const holdIds = rows.map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.retargetDialog.holdIds = holdIds;
            this.retargetDialog.open({}).subscribe(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                }
            );
        }
    }

    showCancelDialog(rows: any[]) {
        const holdIds = rows.map(r => r.id).filter(id => Boolean(id));
        if (holdIds.length > 0) {
            this.cancelDialog.holdIds = holdIds;
            this.cancelDialog.open({}).subscribe(
                rowsModified => {
                    if (rowsModified) {
                        this.holdsGrid.reload();
                    }
                }
            );
        }
    }

    printHolds() {
        // Request a page with no limit to get all of the wide holds for
        // printing.  Call requestPage() directly instead of grid.reload()
        // since we may already have the data.

        const pager = new Pager();
        pager.offset = 0;
        pager.limit = null;

        if (this.gridDataSource.sort.length === 0) {
            this.gridDataSource.sort = this.defaultSort;
        }

        this.gridDataSource.requestPage(pager).then(() => {
            if (this.gridDataSource.data.length > 0) {
                this.printer.print({
                    templateName: this.printTemplate || 'holds_for_bib',
                    contextData: this.gridDataSource.data,
                    printContext: 'default'
                });
            }
        });
    }
}




