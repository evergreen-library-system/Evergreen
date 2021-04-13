import {Component, ViewChild, OnInit, AfterViewInit, HostListener} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {CircService, CircDisplayInfo, CheckinParams, CheckinResult
    } from '@eg/staff/share/circ/circ.service';
import {Pager} from '@eg/share/util/pager';
import {BarcodeSelectComponent
    } from '@eg/staff/share/barcodes/barcode-select.component';

interface CheckinGridEntry extends CheckinResult {
    // May need to extend...
    foo?: number; // Empty interfaces are not allowed.
}

@Component({
  templateUrl: 'checkin.component.html',
  styleUrls: ['checkin.component.css']
})
export class CheckinComponent implements OnInit, AfterViewInit {
    checkins: CheckinGridEntry[] = [];
    autoIndex = 0;

    barcode: string;
    backdate: string; // ISO
    fineTally = 0;

    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    private copiesInFlight: {[barcode: string]: boolean} = {};

    @ViewChild('grid') private grid: GridComponent;
    @ViewChild('barcodeSelect') private barcodeSelect: BarcodeSelectComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
        private store: ServerStoreService,
        private circ: CircService,
        public patronService: PatronService
    ) {}

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return from(this.checkins);
        };
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
        this.grid.reload();
    }
}

