import {Component, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {map, filter} from 'rxjs/operators';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridColumn} from '@eg/share/grid/grid';
import {VandelayService, VandelayImportSelection,
    VANDELAY_EXPORT_PATH} from './vandelay.service';

@Component({
  templateUrl: 'queue.component.html'
})
export class QueueComponent implements OnInit, AfterViewInit {

    queueId: number;
    queueType: string; // bib / authority
    queueSource: GridDataSource;
    queuedRecClass: string;
    queueSummary: any;

    filters = {
        matches: false,
        nonImported: false,
        withErrors: false
    };

    // keep a local copy for convenience
    attrDefs: IdlObject[];

    @ViewChild('queueGrid') queueGrid: GridComponent;
    @ViewChild('confirmDelDlg') confirmDelDlg: ConfirmDialogComponent;
    @ViewChild('progressDlg') progressDlg: ProgressDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private vandelay: VandelayService) {

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.queueType = params.get('qtype');
            this.queueId = +params.get('id');
        });

        this.queueSource = new GridDataSource();
        this.queueSource.getRows = (pager: Pager) => {
            this.vandelay.queuePageOffset = pager.offset;
            return this.loadQueueRecords(pager);
        };

    }

    ngOnInit() {
    }

    limitToMatches(checked: boolean) {
        this.filters.matches = checked;
        this.queueGrid.reload();
    }

    limitToNonImported(checked: boolean) {
        this.filters.nonImported = checked;
        this.queueGrid.reload();
    }

    limitToImportErrors(checked: boolean) {
        this.filters.withErrors = checked;
        this.queueGrid.reload();
    }

    queuePageOffset(): number {
        return this.vandelay.queuePageOffset;
    }

    ngAfterViewInit() {
        if (this.queueType) {
            this.applyQueueType();
            if (this.queueId) {
                this.loadQueueSummary();
            }
        }
    }

    openRecord(row: any) {
        if (this.queueType === 'auth') {
            this.queueType = 'authority';
        }
        const url =
          `/staff/cat/vandelay/queue/${this.queueType}/${this.queueId}/record/${row.id}/marc`;
        this.router.navigate([url]);
    }

    applyQueueType() {
        this.queuedRecClass = this.queueType.match(/bib/) ? 'vqbr' : 'vqar';
        this.vandelay.getAttrDefs(this.queueType).then(
            attrs => {
                this.attrDefs = attrs;
                // Add grid columns for record attributes
                attrs.forEach(attr => {
                    const col = new GridColumn();
                    col.name = attr.code(),
                    col.label = attr.description(),
                    col.datatype = 'string';
                    this.queueGrid.context.columnSet.add(col);
                });

                // Reapply the grid configuration now that we've
                // dynamically added columns.
                this.queueGrid.context.applyGridConfig();
            }
        );
    }

    qtypeShort(): string {
        return this.queueType === 'bib' ? 'bib' : 'auth';
    }

    loadQueueSummary(): Promise<any> {
        const method =
            `open-ils.vandelay.${this.qtypeShort()}_queue.summary.retrieve`;

        return this.net.request(
            'open-ils.vandelay', method, this.auth.token(), this.queueId)
        .toPromise().then(sum => this.queueSummary = sum);
    }

    loadQueueRecords(pager: Pager): Observable<any> {

        const options = {
            clear_marc: true,
            offset: pager.offset,
            limit: pager.limit,
            flesh_import_items: true,
            non_imported: this.filters.nonImported,
            with_import_error: this.filters.withErrors
        };

        return this.vandelay.getQueuedRecords(
            this.queueId, this.queueType, options, this.filters.matches).pipe(
        filter(rec => {
            // avoid sending mishapen data to the grid
            // this happens (among other reasons) when the grid
            // no longer exists
            const e = this.evt.parse(rec);
            if (e) { console.error(e); return false; }
            return true;
        }),
        map(rec => {
            const recHash: any = {
                id: rec.id(),
                import_error: rec.import_error(),
                error_detail: rec.error_detail(),
                import_time: rec.import_time(),
                imported_as: rec.imported_as(),
                import_items: [],
                error_items: [],
                matches: rec.matches()
            };

            if (this.queueType === 'bib') {
                recHash.import_items = rec.import_items();
                recHash.error_items = rec.import_items().filter(i => i.import_error());
            }

            // Link the record attribute values to the root record
            // object so the grid can find them.
            rec.attributes().forEach(attr => {
                const def =
                    this.attrDefs.filter(d => d.id() === attr.field())[0];
                recHash[def.code()] = attr.attr_value();
            });

            return recHash;
        }));
    }

    findOrCreateImportSelection() {
        let selection = this.vandelay.importSelection;
        if (!selection) {
            selection = new VandelayImportSelection();
            this.vandelay.importSelection = selection;
        }
        selection.queue = this.queueSummary.queue;
        return selection;
    }

    hasOverlayTarget(rid: number): boolean {
        return this.vandelay.importSelection &&
            Boolean(this.vandelay.importSelection.overlayMap[rid]);
    }

    importSelected() {
        const rows = this.queueGrid.context.getSelectedRows();
        if (rows.length) {
            const selection = this.findOrCreateImportSelection();
            selection.recordIds = rows.map(row => row.id);
            console.log('importing: ', this.vandelay.importSelection);
            this.router.navigate(['/staff/cat/vandelay/import']);
        }
    }

    importAll() {
        const selection = this.findOrCreateImportSelection();
        selection.importQueue = true;
        this.router.navigate(['/staff/cat/vandelay/import']);
    }

    deleteQueue() {
        this.confirmDelDlg.open().then(
            yes => {
                this.progressDlg.open();
                return this.net.request(
                    'open-ils.vandelay',
                    `open-ils.vandelay.${this.qtypeShort()}_queue.delete`,
                    this.auth.token(), this.queueId
                ).toPromise();
            },
            no => {
                this.progressDlg.close();
                return Promise.reject('delete failed');
            }
        ).then(
            resp => {
                this.progressDlg.close();
                const e = this.evt.parse(resp);
                if (e) {
                    console.error(e);
                    alert(e);
                } else {
                    // Jump back to the main queue page.
                    this.router.navigate(['/staff/cat/vandelay/queue']);
                }
            },
            err => {
                this.progressDlg.close();
            }
        );
    }

    exportNonImported() {
        this.vandelay.exportQueue(this.queueSummary.queue, true);
    }
}

