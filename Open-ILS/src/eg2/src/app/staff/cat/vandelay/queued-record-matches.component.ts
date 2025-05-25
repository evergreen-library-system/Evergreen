import {Component, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Observable} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {BibRecordService, BibRecordSummary} from '@eg/share/catalog/bib-record.service';
import {VandelayService, VandelayImportSelection} from './vandelay.service';

@Component({
    selector: 'eg-queued-record-matches',
    templateUrl: 'queued-record-matches.component.html'
})
export class QueuedRecordMatchesComponent {

    @Input() queueType: string;
    @Input() recordId: number;
    @ViewChild('bibGrid', { static: false }) bibGrid: GridComponent;
    @ViewChild('authGrid', { static: false }) authGrid: GridComponent;

    queuedRecord: IdlObject;
    bibDataSource: GridDataSource;
    authDataSource: GridDataSource;
    markOverlayTarget: (rows: any[]) => any;
    matchRowClick: (row: any) => void;
    matchMap: {[id: number]: IdlObject};

    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private bib: BibRecordService,
        private vandelay: VandelayService) {

        this.bibDataSource = new GridDataSource();
        this.authDataSource = new GridDataSource();

        this.bibDataSource.getRows = (pager: Pager) => {
            return this.getBibMatchRows(pager);
        };

        this.cellTextGenerator = {
            selected: row => this.isOverlayTarget(row.id) + '',
            eg_record: row => row.eg_record + ''
        };


        /* TODO
        this.authDataSource.getRows = (pager: Pager) => {
        }
        */

        // Mark or un-mark as row as the merge target on row click
        this.matchRowClick = (row: any) => {
            this.toggleMergeTarget(row.id);
        };
    }

    toggleMergeTarget(matchId: number) {

        if (this.isOverlayTarget(matchId)) {

            // clear selection on secondary click;
            delete this.vandelay.importSelection.overlayMap[this.recordId];

        } else {
            // Add to selection.
            // Start a new one if necessary, which will be adopted
            // and completed by the queue UI before import.

            let selection = this.vandelay.importSelection;
            if (!selection) {
                selection = new VandelayImportSelection();
                this.vandelay.importSelection = selection;
            }
            const match = this.matchMap[matchId];
            selection.overlayMap[this.recordId] = match.eg_record();
        }
    }

    isOverlayTarget(matchId: number): boolean {
        const selection = this.vandelay.importSelection;
        if (selection) {
            const match = this.matchMap[matchId];
            return selection.overlayMap[this.recordId] === match.eg_record();
        }
        return false;
    }

    // This thing is a nesty beast -- clean it up
    getBibMatchRows(pager: Pager): Observable<any> {

        return new Observable(observer => {

            this.getQueuedRecord().then(() => {

                const matches = this.queuedRecord.matches();
                const recIds = [];
                this.matchMap = {};
                matches.forEach(m => {
                    this.matchMap[m.id()] = m;
                    if (!recIds.includes(m.eg_record())) {
                        recIds.push(m.eg_record());
                    }
                });

                const bibSummaries: {[id: number]: BibRecordSummary} = {};
                this.bib.getBibSummaries(recIds).subscribe(
                    { next: summary => bibSummaries[summary.id] = summary, error: (err: unknown) => {}, complete: ()  => {
                        matches.forEach(match => {
                            const row = {
                                id: match.id(),
                                eg_record: match.eg_record(),
                                bre_quality: match.quality(),
                                vqbr_quality: this.queuedRecord.quality(),
                                match_score: match.match_score(),
                                bib_summary: bibSummaries[match.eg_record()]
                            };

                            observer.next(row);
                        });

                        observer.complete();
                    } }
                );
            });
        });
    }

    getQueuedRecord(): Promise<any> {
        if (this.queuedRecord) {
            return Promise.resolve('');
        }
        const idlClass = this.queueType === 'bib' ? 'vqbr' : 'vqar';
        const flesh = {flesh: 1, flesh_fields: {}};
        flesh.flesh_fields[idlClass] = ['matches'];
        return this.pcrud.retrieve(idlClass, this.recordId, flesh)
            .toPromise().then(rec => this.queuedRecord = rec);
    }
}

