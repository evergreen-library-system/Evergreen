import {Component, ViewChild, OnInit, AfterViewInit, HostListener} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from} from 'rxjs';
import {concatMap} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {CircService, CircDisplayInfo, CheckinParams, CheckinResult
    } from '@eg/staff/share/circ/circ.service';
import {BarcodeSelectComponent
    } from '@eg/staff/share/barcodes/barcode-select.component';
import {PrintService} from '@eg/share/print/print.service';
import {MarkDamagedDialogComponent
    } from '@eg/staff/share/holdings/mark-damaged-dialog.component';
import {CopyAlertsDialogComponent
    } from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {BucketDialogComponent
    } from '@eg/staff/share/buckets/bucket-dialog.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {BackdateDialogComponent} from '@eg/staff/share/circ/backdate-dialog.component';

interface CheckinGridEntry extends CheckinResult {
    // May need to extend...
    foo?: number; // Empty interfaces are not allowed.
}

const TRIM_LIST_TO = 20;

const CHECKIN_MODIFIERS = [
    'void_overdues',
    'clear_expired',
    'hold_as_transit',
    'manual_float',
    'no_precat_alert',
    'retarget_holds',
    'retarget_holds_all'
];

const SETTINGS = [
    'circ.checkin.strict_barcode'
];

@Component({
  templateUrl: 'checkin.component.html',
  styleUrls: ['checkin.component.css']
})
export class CheckinComponent implements OnInit, AfterViewInit {
    checkins: CheckinGridEntry[] = [];
    autoIndex = 0;

    barcode: string;
    backdate: string;
    backdateUntilLogout = false;
    fineTally = 0;
    isHoldCapture = false;
    strictBarcode = false;
    trimList = false;
    itemNeverCirced: string;

    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    modifiers: {[key: string]: boolean} = {};

    private copiesInFlight: {[barcode: string]: boolean} = {};

    @ViewChild('grid') private grid: GridComponent;
    @ViewChild('barcodeSelect') private barcodeSelect: BarcodeSelectComponent;
    @ViewChild('markDamagedDialog') private markDamagedDialog: MarkDamagedDialogComponent;
    @ViewChild('copyAlertsDialog') private copyAlertsDialog: CopyAlertsDialogComponent;
    @ViewChild('bucketDialog') private bucketDialog: BucketDialogComponent;
    @ViewChild('itemNeverCircedStr') private itemNeverCircedStr: StringComponent;
    @ViewChild('backdateDialog') private backdateDialog: BackdateDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
        private store: ServerStoreService,
        private circ: CircService,
        private toast: ToastService,
        private printer: PrintService,
        public patronService: PatronService
    ) {}

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return from(this.checkins);
        };

        const setNames =
            CHECKIN_MODIFIERS.map(mod => `eg.circ.checkin.${mod}`)
            .concat(SETTINGS);

        this.store.getItemBatch(setNames).then(sets => {
            CHECKIN_MODIFIERS.forEach(mod =>
                this.modifiers[mod] = sets[`eg.circ.checkin.${mod}`]);

            this.strictBarcode = sets['circ.checkin.strict_barcode'];

            if (this.isHoldCapture) {
                this.modifiers.noop = false;
                this.modifiers.auto_print_holds_transits = true;
            }

        });
    }

    ngAfterViewInit() {
        this.focusInput();
    }

    focusInput() {
        const input = document.getElementById('barcode-input');
        if (input) { input.focus(); }
    }

    checkin(params?: CheckinParams, override?: boolean): Promise<CheckinResult> {
        if (!this.barcode) { return Promise.resolve(null); }

        const promise = params ? Promise.resolve(params) : this.collectParams();

        return promise.then((collectedParams: CheckinParams) => {
            if (!collectedParams) { return null; }

            if (this.copiesInFlight[this.barcode]) {
                console.debug('Item ' + this.barcode + ' is already mid-checkin');
                return null;
            }

            this.copiesInFlight[this.barcode] = true;
            return this.circ.checkin(collectedParams);
        })

        .then((result: CheckinResult) => {
            if (result && result.success) {
                this.gridifyResult(result);
            }
            delete this.copiesInFlight[this.barcode];
            this.resetForm();
            return result;
        })

        .finally(() => delete this.copiesInFlight[this.barcode]);
    }

    collectParams(): Promise<CheckinParams> {

        const params: CheckinParams = {
            copy_barcode: this.barcode,
            backdate: this.backdate
        };

        return this.barcodeSelect.getBarcode('asset', this.barcode)
        .then(selection => {
            if (selection) {
                params.copy_id = selection.id;
                params.copy_barcode = selection.barcode;
                return params;
            } else {
                // User canceled the multi-match selection dialog.
                return null;
            }
        });
    }

    resetForm() {
        this.barcode = '';
        this.focusInput();
    }

    gridifyResult(result: CheckinResult) {
        const entry: CheckinGridEntry = result;
        entry.index = this.autoIndex++;

        if (result.copy) {
            result.copy.circ_lib(this.org.get(result.copy.circ_lib()));
        }

        if (result.mbts) {
            this.fineTally =
                ((this.fineTally * 100) + (result.mbts.balance_owed() * 100)) / 100;
        }

        this.checkins.unshift(entry);

        if (this.trimList && this.checkins.length >= TRIM_LIST_TO) {
            this.checkins.length = TRIM_LIST_TO;
        }
        this.grid.reload();
    }

    toggleMod(mod: string) {
        if (this.modifiers[mod]) {
            this.modifiers[mod] = false;
            this.store.removeItem('eg.circ.checkin.' + mod);
        } else {
            this.modifiers[mod] = true;
            this.store.setItem('eg.circ.checkin.' + mod, true);
        }
    }

    toggleStrictBarcode(active: boolean) {
        if (active) {
            this.store.setItem('circ.checkin.strict_barcode', true);
        } else {
            this.store.removeItem('circ.checkin.strict_barcode');
        }
    }

    printReceipt() {
        if (this.checkins.length === 0) { return; }

        this.printer.print({
            printContext: 'default',
            templateName: 'checkin',
            contextData: {checkins: this.checkins}
        });
    }

    hasAlerts(): boolean {
        return (
            Boolean(this.backdate)              ||
            this.modifiers.noop                 ||
            this.modifiers.manual_float         ||
            this.modifiers.void_overdues        ||
            this.modifiers.clear_expired        ||
            this.modifiers.retarget_holds       ||
            this.modifiers.hold_as_transit      ||
            this.modifiers.no_precat_alert      ||
            this.modifiers.do_inventory_update  ||
            this.modifiers.auto_print_holds_transits
        );
    }

    getCopyIds(rows: CheckinGridEntry[], skipStatus?: number): number[] {
        return this.getCopies(rows, skipStatus).map(c => Number(c.id()));
    }

    getCopies(rows: CheckinGridEntry[], skipStatus?: number): IdlObject[] {
        let copies = rows.filter(r => r.copy).map(r => r.copy);
        if (skipStatus) {
            copies = copies.filter(
                c => Number(c.status().id()) !== Number(skipStatus));
        }
        return copies;
    }


    markDamaged(rows: CheckinGridEntry[]) {
        const copyIds = this.getCopyIds(rows, 14 /* ignore damaged */);
        if (copyIds.length === 0) { return; }

        from(copyIds).pipe(concatMap(id => {
            this.markDamagedDialog.copyId = id;
            return this.markDamagedDialog.open({size: 'lg'});
        }));
    }

    addItemAlerts(rows: CheckinGridEntry[]) {
        const copyIds = this.getCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.mode = 'create';
        this.copyAlertsDialog.open({size: 'lg'}).subscribe();
    }

    manageItemAlerts(rows: CheckinGridEntry[]) {
        const copyIds = this.getCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.mode = 'manage';
        this.copyAlertsDialog.open({size: 'lg'}).subscribe();
    }

    openBucketDialog(rows: CheckinGridEntry[]) {
        const copyIds = this.getCopyIds(rows);
        if (copyIds.length > 0) {
            this.bucketDialog.bucketClass = 'copy';
            this.bucketDialog.itemIds = copyIds;
            this.bucketDialog.open({size: 'lg'});
        }
    }

    retrieveLastPatron(rows: CheckinGridEntry[]) {
        const copy = this.getCopies(rows).pop();
        if (!copy) { return; }

        this.circ.lastCopyCirc(copy.id()).then(circ => {
            if (circ) {
                this.router.navigate(['/staff/circ/patron', circ.usr(), 'checkout']);
            } else {
                this.itemNeverCirced = copy.barcode();
                setTimeout(() => this.toast.danger(this.itemNeverCircedStr.text));
            }
        });
    }

    backdatePostCheckin(rows: CheckinGridEntry[]) {
        const circs = rows.map(r => r.circ).filter(circ => Boolean(circ));
        if (circs.length === 0) { return; }

        this.backdateDialog.circIds = circs.map(c => c.id());
        this.backdateDialog.open().subscribe(backdate => {
            if (backdate) {
                circs.forEach(circ => circ.checkin_time(backdate));
            }
        });
    }
}

