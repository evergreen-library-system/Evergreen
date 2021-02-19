import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Observable, empty, of, from} from 'rxjs';
import {map, tap, switchMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CheckoutParams, CheckoutResult, CircService} from './circ.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CopyAlertsDialogComponent
    } from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {ArrayUtil} from '@eg/share/util/array';

export interface CircGridEntry {
    title?: string;
    author?: string;
    isbn?: string;
    copy?: IdlObject;
    circ?: IdlObject;
    dueDate?: string;
    copyAlertCount?: number;
    nonCatCount?: number;
}

const CIRC_FLESH_DEPTH = 4;
const CIRC_FLESH_FIELDS = {
  circ: ['target_copy', 'workstation', 'checkin_workstation'],
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

    entries: CircGridEntry[] = null;
    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    @ViewChild('circGrid') private circGrid: GridComponent;
    @ViewChild('copyAlertsDialog')
        private copyAlertsDialog: CopyAlertsDialogComponent;

    constructor(
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        public circ: CircService,
        private audio: AudioService,
        private store: StoreService,
        private serverStore: ServerStoreService
    ) {}

    ngOnInit() {

        // The grid never fetches data directly.
        // The caller is responsible initiating all data loads.
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            if (this.entries) {
                return from(this.entries);
            } else {
                return empty();
            }
        };

        this.cellTextGenerator = {
            title: row => row.title
        };
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

        return this.pcrud.search('circ', {id: circIds}, {
            flesh: CIRC_FLESH_DEPTH,
            flesh_fields: CIRC_FLESH_FIELDS,
            order_by : {circ : ['xact_start']},

            // Avoid fetching the MARC blob by specifying which
            // fields on the bre to select.  More may be needed.
            // Note that fleshed fields are explicitly selected.
            select: {bre : ['id']}

        }).pipe(map(circ => {

            const entry = this.gridify(circ);
            this.entries.push(entry);
            return entry;
        }));
    }

    gridify(circ: IdlObject): CircGridEntry {

        const entry: CircGridEntry = {
            circ: circ,
            dueDate: circ.due_date(),
            copyAlertCount: 0 // TODO
        };

        const copy = circ.target_copy();
        entry.copy = copy;

        // Some values have to be manually extracted / normalized
        if (copy.call_number().id() === -1) {

            entry.title = copy.dummy_title();
            entry.author = copy.dummy_author();
            entry.isbn = copy.dummy_isbn();

        } else {

            const display =
                copy.call_number().record().wide_display_entry();

            entry.title = display.title();
            entry.author = display.author();
            entry.isbn = display.isbn();
        }

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
        this.copyAlertsDialog.mode = mode;
        this.copyAlertsDialog.open({size: 'lg'}).subscribe(
            modified => {
                if (modified) {
                    // TODO: verify the modiifed alerts are present
                    // or go fetch them.
                    this.circGrid.reload();
                }
            }
        );
    }
}

