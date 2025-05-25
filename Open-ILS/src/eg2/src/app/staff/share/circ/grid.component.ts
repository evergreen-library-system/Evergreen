import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {Observable, empty, from, map, concatWith as concat, ignoreElements, tap, concatMap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CheckoutParams, CheckinParams, CheckinResult,
    CircDisplayInfo, CircService} from './circ.service';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {GridDataSource, GridCellTextGenerator,
    GridRowFlairEntry} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CopyAlertsDialogComponent
} from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {PrintService} from '@eg/share/print/print.service';
import {StringComponent} from '@eg/share/string/string.component';
import {DueDateDialogComponent} from './due-date-dialog.component';
import {MarkDamagedDialogComponent
} from '@eg/staff/share/holdings/mark-damaged-dialog.component';
import {ClaimsReturnedDialogComponent} from './claims-returned-dialog.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {AddBillingDialogComponent} from '@eg/staff/share/billing/billing-dialog.component';

export interface CircGridEntry extends CircDisplayInfo {
    index: string; // class + id -- row index
    circ?: IdlObject;
    dueDate?: string;
    copyAlertCount?: number;
    nonCatCount?: number;
    noticeCount?: number;
    lastNotice?: string; // iso date

    // useful for reporting precaculated values and avoiding
    // repetitive date creation on grid render.
    overdue?: boolean;
}

const CIRC_FLESH_DEPTH = 4;
const CIRC_FLESH_FIELDS = {
    circ: ['target_copy', 'workstation', 'checkin_workstation', 'circ_lib'],
    acp:  [
        'call_number',
        'holds_count',
        'status',
        'circ_lib',
        'location',
        'floating',
        'age_protect',
        'parts'
    ],
    acpm: ['part'],
    acn:  ['record', 'owning_lib', 'prefix', 'suffix'],
    bre:  ['wide_display_entry']
};

@Component({
    templateUrl: 'grid.component.html',
    selector: 'eg-circ-grid'
})
export class CircGridComponent implements OnInit {

    @Input() persistKey: string;
    @Input() printTemplate: string; // defaults to items_out
    @Input() menuStyle: 'full' | 'slim' | 'none' = 'full';

    @Input() sortField: string; // e.g. "due_date", "due_date DESC"

    // Override default grid page size
    @Input() pageSize: number = null;

    // Emitted when a grid action modified data in a way that could
    // affect which cirulcations should appear in the grid.  Caller
    // should then refresh their data and call the load() or
    // appendGridEntry() function.
    @Output() reloadRequested: EventEmitter<void> = new EventEmitter<void>();

    entries: CircGridEntry[] = null;
    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    rowFlair: (row: CircGridEntry) => GridRowFlairEntry;
    rowClass: (row: CircGridEntry) => string;
    claimsNeverCount = 0;

    nowDate: number = new Date().getTime();

    @ViewChild('overdueString') private overdueString: StringComponent;
    @ViewChild('circGrid') private circGrid: GridComponent;
    @ViewChild('copyAlertsDialog')
    private copyAlertsDialog: CopyAlertsDialogComponent;
    @ViewChild('dueDateDialog') private dueDateDialog: DueDateDialogComponent;
    @ViewChild('markDamagedDialog')
    private markDamagedDialog: MarkDamagedDialogComponent;
    @ViewChild('itemsOutConfirm')
    private itemsOutConfirm: ConfirmDialogComponent;
    @ViewChild('claimsReturnedConfirm')
    private claimsReturnedConfirm: ConfirmDialogComponent;
    @ViewChild('claimsNeverConfirm')
    private claimsNeverConfirm: ConfirmDialogComponent;
    @ViewChild('progressDialog')
    private progressDialog: ProgressDialogComponent;
    @ViewChild('claimsReturnedDialog')
    private claimsReturnedDialog: ClaimsReturnedDialogComponent;
    @ViewChild('addBillingDialog')
    private addBillingDialog: AddBillingDialogComponent;

    constructor(
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        public circ: CircService,
        private audio: AudioService,
        private store: StoreService,
        private printer: PrintService,
        private toast: ToastService,
        private serverStore: ServerStoreService
    ) {}

    ngOnInit() {

        // The grid never fetches data directly.
        // The caller is responsible initiating all data loads.
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            if (!this.entries) { return empty(); }

            const page = this.entries.slice(pager.offset, pager.offset + pager.limit)
                .filter(entry => entry !== undefined);

            return from(page);
        };

        this.cellTextGenerator = {
            title: row => row.title,
            'copy.barcode': row => row.copy ? row.copy.barcode() : ''
        };

        this.rowFlair = (row: CircGridEntry) => {
            if (this.circIsOverdue(row)) {
                return {icon: 'error_outline', title: this.overdueString.text};
            }
        };

        this.rowClass = (row: CircGridEntry) => {
            if (this.circIsOverdue(row)) {
                return 'less-intense-alert';
            }
        };
    }

    reportError(err: any) {
        console.error('Circ error occurred: ' + err);
        this.toast.danger(err); // EgEvent has a toString()
    }

    // Ask the caller to update our data set.
    emitReloadRequest() {
        this.entries = null;
        this.reloadRequested.emit();
    }

    // Reload the grid without any data retrieval
    reloadGrid() {
        this.circGrid.reload();
    }

    // Fetch circulation data and make it available to the grid.
    load(circIds: number[]): Observable<CircGridEntry> {

        // No circs to load
        if (!circIds || circIds.length === 0) { return empty(); }

        // Return the circs we have already retrieved.
        if (this.entries) { return from(this.entries); }

        this.entries = [];

        // fetchCircs and fetchNotices both return observable of grid entries.
        // ignore the entries from fetchCircs so they are not duplicated.
        return this.fetchCircs(circIds)
            .pipe(ignoreElements(), concat(this.fetchNotices(circIds)));
    }

    fetchCircs(circIds: number[]): Observable<CircGridEntry> {

        return this.pcrud.search('circ', {id: circIds}, {
            flesh: CIRC_FLESH_DEPTH,
            flesh_fields: CIRC_FLESH_FIELDS,
            order_by : {circ: this.sortField ? this.sortField : 'xact_start'},

            // Avoid fetching the MARC blob by specifying which
            // fields on the bre to select.  More may be needed.
            // Note that fleshed fields are explicitly selected.
            select: {bre : ['id']}

        }).pipe(map(circ => {

            const entry = this.gridify(circ);
            this.appendGridEntry(entry);
            return entry;
        }));
    }

    fetchNotices(circIds: number[]): Observable<CircGridEntry> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.itemsout.notices',
            this.auth.token(), circIds
        ).pipe(tap(notice => {

            const entry = this.entries.filter(
                e => e.circ.id() === Number(notice.circ_id))[0];

            entry.noticeCount = notice.numNotices;
            entry.lastNotice = notice.lastDt;
            return entry;
        }));
    }

    // Also useful for manually appending circ-like things (e.g. noncat
    // circs) that can be massaged into CircGridEntry structs.
    appendGridEntry(entry: CircGridEntry) {
        if (!this.entries) { this.entries = []; }
        this.entries.push(entry);
    }

    gridify(circ: IdlObject): CircGridEntry {

        const circDisplay = this.circ.getDisplayInfo(circ);

        const entry: CircGridEntry = {
            index: `circ-${circ.id()}`,
            circ: circ,
            dueDate: circ.due_date(),
            title: circDisplay.title,
            author: circDisplay.author,
            isbn: circDisplay.isbn,
            copy: circDisplay.copy,
            volume: circDisplay.volume,
            record: circDisplay.copy,
            display: circDisplay.display,
            copyAlertCount: 0 // TODO
        };

        return entry;
    }

    selectedCopyIds(rows: CircGridEntry[]): number[] {
        return rows
            .filter(row => row.copy)
            .map(row => Number(row.copy.id()));
    }

    openItemAlerts(rows: CircGridEntry[], mode: string) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        // this.copyAlertsDialog.mode = mode;
        this.copyAlertsDialog.open({size: 'lg'}).subscribe(
            modified => {
                if (modified) {
                    // TODO: verify the modified alerts are present
                    // or go fetch them.
                    this.circGrid.reload();
                }
            }
        );
    }

    // Which copies in the grid are selected.
    getCopyIds(rows: CircGridEntry[], skipStatus?: number): number[] {
        return this.getCopies(rows, skipStatus).map(c => Number(c.id()));
    }

    getCopies(rows: CircGridEntry[], skipStatus?: number): IdlObject[] {
        let copies = rows.filter(r => r.copy).map(r => r.copy);
        if (skipStatus) {
            copies = copies.filter(
                c => Number(c.status().id()) !== Number(skipStatus));
        }
        return copies;
    }

    getCircIds(rows: CircGridEntry[]): number[] {
        return this.getCircs(rows).map(row => Number(row.id()));
    }

    getCircs(rows: any): IdlObject[] {
        return rows.filter(r => r.circ).map(r => r.circ);
    }

    printReceipts(rows: any) {
        if (rows.length > 0) {
            this.printer.print({
                templateName: this.printTemplate || 'items_out',
                contextData: {circulations: rows},
                printContext: 'default'
            });
        }
    }

    editDueDate(rows: any) {
        const ids = this.getCircIds(rows);
        if (ids.length === 0) { return; }

        this.dueDateDialog.open().subscribe(isoDate => {
            if (!isoDate) { return; } // canceled

            const dialog = this.openProgressDialog(rows);

            from(ids).pipe(concatMap(id => {
                return this.net.request(
                    'open-ils.circ',
                    'open-ils.circ.circulation.due_date.update',
                    this.auth.token(), id, isoDate
                );
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            })).subscribe(
                { next: circ => {
                    const row = rows.filter(r => r.circ.id() === circ.id())[0];
                    row.circ.due_date(circ.due_date());
                    row.dueDate = circ.due_date();
                    delete row.overdue; // it will recalculate
                    dialog.increment();
                }, error: (err: unknown)  => console.log(err), complete: ()   => {
                    dialog.close();
                    this.emitReloadRequest();
                } }
            );
        });
    }

    circIsOverdue(row: CircGridEntry): boolean {
        const circ = row.circ;

        if (!circ) { return false; } // noncat

        if (row.overdue === undefined) {

            if (circ.stop_fines() &&
                // Items that aren't really checked out can't be overdue.
                circ.stop_fines().match(/LOST|CLAIMSRETURNED|CLAIMSNEVERCHECKEDOUT/)) {
                row.overdue = false;
            } else {
                row.overdue = (Date.parse(circ.due_date()) < this.nowDate);
            }
        }
        return row.overdue;
    }

    markDamaged(rows: CircGridEntry[]) {
        // eslint-disable-next-line no-magic-numbers
        const copyIds = this.getCopyIds(rows, 14 /* ignore damaged */);

        if (copyIds.length === 0) { return; }

        let rowsModified = false;

        const markNext = (ids: number[]): Promise<any> => {
            if (ids.length === 0) {
                return Promise.resolve();
            }

            this.markDamagedDialog.copyId = ids.pop();

            return this.markDamagedDialog.open({size: 'lg'})
                .toPromise().then(ok => {
                    if (ok) { rowsModified = true; }
                    return markNext(ids);
                });
        };

        markNext(copyIds).then(_ => {
            if (rowsModified) {
                this.emitReloadRequest();
            }
        });
    }

    openProgressDialog(rows: CircGridEntry[]): ProgressDialogComponent {
        this.progressDialog.update({value: 0, max: rows.length});
        this.progressDialog.open();
        return this.progressDialog;
    }


    renewAll() {
        this.renew(this.entries);
    }

    renew(rows: CircGridEntry[]) {

        const dialog = this.openProgressDialog(rows);
        const params: CheckoutParams = {};
        let refreshNeeded = false;

        return this.circ.renewBatch(this.getCopyIds(rows))
            .subscribe(
                { next: result => {
                    dialog.increment();
                    // Value can be null when dialogs are canceled
                    if (result) { refreshNeeded = true; }
                }, error: (err: unknown) => this.reportError(err), complete: () => {
                    dialog.close();
                    if (refreshNeeded) {
                        this.emitReloadRequest();
                    }
                } }
            );
    }

    renewWithDate(rows: any) {
        const ids = this.getCopyIds(rows);
        if (ids.length === 0) { return; }

        this.dueDateDialog.open().subscribe(isoDate => {
            if (!isoDate) { return; } // canceled

            const dialog = this.openProgressDialog(rows);
            const params: CheckoutParams = {due_date: isoDate};

            let refreshNeeded = false;
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            this.circ.renewBatch(ids).subscribe(
                { next: resp => {
                    if (resp.success) { refreshNeeded = true; }
                    dialog.increment();
                }, error: (err: unknown) => this.reportError(err), complete: () => {
                    dialog.close();
                    if (refreshNeeded) {
                        this.emitReloadRequest();
                    }
                } }
            );
        });
    }


    // Same params will be used for each copy
    checkin(rows: CircGridEntry[], params?:
        CheckinParams, noReload?: boolean): Observable<CheckinResult> {

        const dialog = this.openProgressDialog(rows);

        let changesApplied = false;
        return this.circ.checkinBatch(this.getCopyIds(rows), params)
            .pipe(tap(
                { next: result => {
                    if (result) { changesApplied = true; }
                    dialog.increment();
                }, error: (err: unknown) => this.reportError(err), complete: () => {
                    dialog.close();
                    if (changesApplied && !noReload) { this.emitReloadRequest(); }
                } }
            ));
    }

    markLost(rows: CircGridEntry[]) {
        const dialog = this.openProgressDialog(rows);
        const barcodes = this.getCopies(rows).map(c => c.barcode());

        from(barcodes).pipe(concatMap(barcode => {
            return this.net.request(
                'open-ils.circ',
                'open-ils.circ.circulation.set_lost',
                this.auth.token(), {barcode: barcode}
            );
        })).subscribe(
            { next: result => dialog.increment(), error: (err: unknown) => this.reportError(err), complete: () => {
                dialog.close();
                this.emitReloadRequest();
            } }
        );
    }

    claimsReturned(rows: CircGridEntry[]) {
        this.claimsReturnedDialog.barcodes =
            this.getCopies(rows).map(c => c.barcode());

        this.claimsReturnedDialog.open().subscribe(
            rowsModified => {
                if (rowsModified) {
                    this.emitReloadRequest();
                }
            }
        );
    }

    claimsNeverCheckedOut(rows: CircGridEntry[]) {
        const dialog = this.openProgressDialog(rows);

        this.claimsNeverCount = rows.length;

        this.claimsNeverConfirm.open().subscribe(confirmed => {
            this.claimsNeverCount = 0;

            if (!confirmed) {
                dialog.close();
                return;
            }

            this.circ.checkinBatch(
                this.getCopyIds(rows), {claims_never_checked_out: true}
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            ).subscribe(
                { next: result => dialog.increment(), error: (err: unknown) => this.reportError(err), complete: () => {
                    dialog.close();
                    this.emitReloadRequest();
                } }
            );
        });
    }

    openBillingDialog(rows: CircGridEntry[]) {

        let changesApplied = false;

        from(this.getCircIds(rows))
            .pipe(concatMap(id => {
                this.addBillingDialog.xactId = id;
                return this.addBillingDialog.open();
            }))
            .subscribe(
                { next: changes => {
                    if (changes) { changesApplied = true; }
                }, error: (err: unknown) => this.reportError(err), complete: ()  => {
                    if (changesApplied) {
                        this.emitReloadRequest();
                    }
                } }
            );
    }

    showRecentCircs(rows: CircGridEntry[]) {
        const copyId = this.getCopyIds(rows)[0];
        if (copyId) {
            window.open('/eg/staff/cat/item/' + copyId + '/circ_list');
        }
    }

    showTriggeredEvents(rows: CircGridEntry[]) {
        const copyId = this.getCopyIds(rows)[0];
        if (copyId) {
            window.open('/eg/staff/cat/item/' + copyId + '/triggered_events');
        }
    }
}

