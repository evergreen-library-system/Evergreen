/* eslint-disable no-magic-numbers */
import {Component, ViewChild, OnInit, AfterViewInit} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute} from '@angular/router';
import {empty, from, concatMap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {CircService, CircDisplayInfo, CheckoutParams, CheckoutResult
} from '@eg/staff/share/circ/circ.service';
import {BarcodeSelectComponent
} from '@eg/staff/share/barcodes/barcode-select.component';
import {PrintService} from '@eg/share/print/print.service';
import {MarkDamagedDialogComponent
} from '@eg/staff/share/holdings/mark-damaged-dialog.component';
import {CopyAlertsDialogComponent
} from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {CancelTransitDialogComponent
} from '@eg/staff/share/circ/cancel-transit-dialog.component';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';


interface RenewGridEntry extends CheckoutResult {
    // May need to extend...
    foo?: number; // Empty interfaces are not allowed.
}

const TRIM_LIST_TO = 20;

@Component({
    templateUrl: 'renew.component.html',
    styleUrls: ['renew.component.css']
})
export class RenewComponent implements OnInit, AfterViewInit {
    renewals: RenewGridEntry[] = [];
    autoIndex = 0;

    barcode: string;
    dueDate: string;
    useDueDate = false;
    fineTally = 0;
    strictBarcode = false;
    trimList = false;
    itemNeverCirced: string;

    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    private copiesInFlight: {[barcode: string]: boolean} = {};

    @ViewChild('grid') private grid: GridComponent;
    @ViewChild('barcodeSelect') private barcodeSelect: BarcodeSelectComponent;
    @ViewChild('markDamagedDialog') private markDamagedDialog: MarkDamagedDialogComponent;
    @ViewChild('copyAlertsDialog') private copyAlertsDialog: CopyAlertsDialogComponent;
    @ViewChild('itemNeverCircedStr') private itemNeverCircedStr: StringComponent;
    @ViewChild('cancelTransitDialog') private cancelTransitDialog: CancelTransitDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private ngLocation: Location,
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
        private store: ServerStoreService,
        private circ: CircService,
        private toast: ToastService,
        private printer: PrintService,
        private holdings: HoldingsService,
        private anonCache: AnonCacheService,
        public patronService: PatronService
    ) {}

    ngOnInit() {

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return from(this.renewals);
        };

        this.store.getItemBatch(['circ.renew.strict_barcode'])
            .then(sets => {
                this.strictBarcode = sets['circ.renew.strict_barcode'];
            }).then(_ => this.circ.applySettings());
    }

    ngAfterViewInit() {
        this.focusInput();
    }

    focusInput() {
        const input = document.getElementById('barcode-input');
        if (input) { input.focus(); }
    }

    renew(params?: CheckoutParams, override?: boolean): Promise<CheckoutResult> {
        if (!this.barcode) { return Promise.resolve(null); }

        const promise = params ? Promise.resolve(params) : this.collectParams();

        return promise.then((collectedParams: CheckoutParams) => {
            if (!collectedParams) { return null; }

            if (this.copiesInFlight[this.barcode]) {
                console.debug('Item ' + this.barcode + ' is already mid-renewal');
                return null;
            }

            this.copiesInFlight[this.barcode] = true;
            return this.circ.renew(collectedParams);
        })

            .then((result: CheckoutResult) => {
                if (result && result.success) {
                    this.gridifyResult(result);
                }
                delete this.copiesInFlight[this.barcode];
                this.resetForm();
                return result;
            })

            .finally(() => delete this.copiesInFlight[this.barcode]);
    }

    collectParams(): Promise<CheckoutParams> {

        const params: CheckoutParams = {
            copy_barcode: this.barcode,
            due_date: this.useDueDate ? this.dueDate : null,
            _checkbarcode: this.strictBarcode
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

    gridifyResult(result: CheckoutResult) {
        const entry: RenewGridEntry = result;
        entry.index = this.autoIndex++;

        if (result.copy) {
            result.copy.circ_lib(this.org.get(result.copy.circ_lib()));
        }

        if (result.mbts) {
            this.fineTally =
                ((this.fineTally * 100) + (result.mbts.balance_owed() * 100)) / 100;
        }

        this.renewals.unshift(entry);

        if (this.trimList && this.renewals.length >= TRIM_LIST_TO) {
            this.renewals.length = TRIM_LIST_TO;
        }
        this.grid.reload();
    }

    toggleStrictBarcode(active: boolean) {
        if (active) {
            this.store.setItem('circ.renew.strict_barcode', true);
        } else {
            this.store.removeItem('circ.renew.strict_barcode');
        }
    }

    printReceipt() {
        if (this.renewals.length === 0) { return; }

        this.printer.print({
            printContext: 'default',
            templateName: 'renew',
            contextData: {renewals: this.renewals}
        });
    }

    getCopyIds(rows: RenewGridEntry[], skipStatus?: number): number[] {
        return this.getCopies(rows, skipStatus).map(c => Number(c.id()));
    }

    getCopies(rows: RenewGridEntry[], skipStatus?: number): IdlObject[] {
        let copies = rows.filter(r => r.copy).map(r => r.copy);
        if (skipStatus) {
            copies = copies.filter(
                c => Number(c.status().id()) !== Number(skipStatus));
        }
        return copies;
    }


    markDamaged(rows: RenewGridEntry[]) {
        const copyIds = this.getCopyIds(rows, 14 /* ignore damaged */);
        if (copyIds.length === 0) { return; }

        from(copyIds).pipe(concatMap(id => {
            this.markDamagedDialog.copyId = id;
            return this.markDamagedDialog.open({size: 'lg'});
        }));
    }

    addItemAlerts(rows: RenewGridEntry[]) {
        const copyIds = this.getCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.open({size: 'lg'}).subscribe();
    }

    manageItemAlerts(rows: RenewGridEntry[]) {
        const copyIds = this.getCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.open({size: 'lg'}).subscribe();
    }

    retrieveLastPatron(rows: RenewGridEntry[]) {
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

    cancelTransits(rows: RenewGridEntry[]) {

        rows = rows.filter(row => row.copy && row.copy.status().id() === 6);

        // Copies in transit are not always accompanied by their transit.
        from(rows).pipe(concatMap(row => {
            return from(
                this.circ.findCopyTransit(row)
                    .then(transit => row.transit = transit)
            );
        }))
            .pipe(concatMap(_ => {

                const ids = rows
                    .filter(row => Boolean(row.transit))
                    .map(row => row.transit.id());

                if (ids.length > 0) {
                    this.cancelTransitDialog.transitIds = ids;
                    return this.cancelTransitDialog.open();
                } else {
                    return empty();
                }

            })).subscribe();
    }

    showRecentCircs(rows: RenewGridEntry[]) {
        const copyId = this.getCopyIds(rows)[0];
        if (copyId) {
            const url = `/eg/staff/cat/item/${copyId}/circs`;
            window.open(url);
        }
    }
}

