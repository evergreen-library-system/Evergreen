import {ActivatedRoute} from '@angular/router';
import {Component, OnInit, ViewChild} from '@angular/core';
import { of, switchMap, tap, finalize, catchError } from 'rxjs';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {IdlService} from '@eg/core/idl.service';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';

@Component({
    templateUrl: 'attempts.component.html'
})
export class LinkCheckerAttemptsComponent implements OnInit {

    batches: number[] = [];

    batchesIdlClass = 'uvva';
    batchesSessionField = 'session';

    attemptsIdlClass = 'uvuv';
    attemptsSortField = 'id';
    attemptsBatchField = 'attempt';
    attemptsFleshFields = {
        'uvuv' : ['url','attempt'],
        'uvu' : ['item','url_selector','redirect_from'],
        'uvsbrem' : ['target_biblio_record_entry'],
        'bre' : ['simple_record']
    };
    // eslint-disable-next-line no-magic-numbers
    attemptsFleshDepth = 4;
    attemptsIdlClassDef: any;
    attemptsPKeyField: string;

    attemptsPermaCrud: any;
    attemptsPerms: string;

    alertMessage = '';

    @ViewChild('grid', { static: true }) grid: GridComponent;
    dataSource: GridDataSource = new GridDataSource();
    noSelectedRows: boolean;
    oneSelectedRow: boolean;

    constructor(
        private flatData: GridFlatDataService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
    ) {}

    ngOnInit() {

        this.attemptsIdlClassDef = this.idl.classes[this.attemptsIdlClass];
        this.attemptsPKeyField = this.attemptsIdlClassDef.pkey || 'id';

        this.attemptsPermaCrud = this.attemptsIdlClassDef.permacrud || {};
        if (this.attemptsPermaCrud.retrieve) {
            this.attemptsPerms = this.attemptsPermaCrud.retrieve.perms;
        }

        this.route.queryParams.pipe(
            switchMap(params => {
                if (params.alertMessage) {
                    this.alertMessage = params.alertMessage;
                }
                if (params.batches) {
                    this.batches = JSON.parse(params.batches);
                    // Return an observable that immediately completes
                    return of(null);
                } else if (params.sessions) {
                    // Initialize this.batches
                    this.batches = [];
                    const batchSearch = {};
                    batchSearch[this.batchesSessionField] = JSON.parse(params.sessions);
                    // Return the pcrud.search observable
                    return this.pcrud.search(this.batchesIdlClass,batchSearch).pipe(
                        tap((batch) => {
                            this.batches.push(batch.id());
                        }),
                        finalize(() => {
                            this.batches = Array.from(new Set(this.batches));
                            this.grid.reload();
                        }),
                        catchError((err: unknown) => {
                            console.log('pcrud.search.uvs err', err);
                            // Properly handle error, return an observable that immediately completes
                            return of(null);
                        })
                    );
                } else {
                    // Return an observable that immediately completes
                    return of(null);
                }
            })
        ).subscribe(() => {
            // These calls will wait until the previous observables have completed
            this.initDataSource();
            this.gridSelectionChange([]);
            console.log('phasefx',this);
        });
    }

    gridSelectionChange(keys: string[]) {
        this.noSelectedRows = (keys.length === 0);
        this.oneSelectedRow = (keys.length === 1);
        // var rows = this.grid.context.getSelectedRows();
    }

    initDataSource() {
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {

            const query: any = {};

            if (this.batches) {
                query[this.attemptsBatchField] = this.batches;
            }

            let query_filters = [];
            Object.keys(this.dataSource.filters).forEach(key => {
                query_filters = query_filters.concat( this.dataSource.filters[key] );
            });

            if (query_filters.length > 0) {
                query['-and'] = query_filters;
            }

            return this.flatData.getRows(
                this.grid.context, query, pager, sort);
        };
    }
}
