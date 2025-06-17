import {ChangeDetectorRef, Component, Input, OnInit, OnDestroy, ViewChild} from '@angular/core';
import {ActivatedRoute, Router} from '@angular/router';
import {from, Observable, Subject, lastValueFrom, firstValueFrom, defaultIfEmpty, EMPTY,
    map, switchMap, takeUntil, take, catchError} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject,IdlService} from '@eg/core/idl.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {RecordBucketService} from '@eg/staff/cat/buckets/record/record-bucket.service';
import {RecordBucketStateService} from '@eg/staff/cat/buckets/record/record-bucket-state.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {Pager} from '@eg/share/util/pager';
import {BucketTransferDialogComponent} from '@eg/staff/share/buckets/bucket-transfer-dialog.component';
import {BucketShareDialogComponent} from '@eg/staff/share/buckets/bucket-share-dialog.component';
import {BucketDialogComponent} from '@eg/staff/share/buckets/bucket-dialog.component';
import {BucketActionSummaryDialogComponent} from '@eg/staff/share/buckets/bucket-action-summary-dialog.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {RecordBucketExportDialogComponent} from '@eg/staff/cat/buckets/record/record-bucket-export-dialog.component';
import {RecordBucketItemUploadDialogComponent} from '@eg/staff/cat/buckets/record/record-bucket-item-upload-dialog.component';

/**
 * Record bucket grid interface
 */

@Component({
    selector: 'eg-record-bucket',
    templateUrl: 'record-bucket.component.html',
    styleUrls: ['./record-bucket.component.css']
})

export class RecordBucketComponent implements OnInit, OnDestroy {

    @Input() userId: Number;

    private initInProgress = true;
    private destroy$ = new Subject<void>();

    @ViewChild('grid', { static: true }) private grid: GridComponent;
    cellTextGenerator: GridCellTextGenerator;
    dataSource: GridDataSource;
    bucketIdToRetrieve: number;
    jumpToContentsOnRetrieveById = false;
    noSelectedRows: boolean;
    oneSelectedRow: boolean;

    @ViewChild('transferDialog', { static: true }) transferDialog: BucketTransferDialogComponent;
    @ViewChild('shareBucketDialog', { static: true }) shareBucketDialog: BucketShareDialogComponent;
    @ViewChild('newBucketDialog', { static: true }) newBucketDialog: BucketDialogComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('deleteDialog', { static: true }) deleteDialog: ConfirmDialogComponent;
    @ViewChild('deleteCarouselDialog', { static: true }) deleteCarouselDialog: ConfirmDialogComponent;
    @ViewChild('deleteFail', { static: true }) deleteFail: AlertDialogComponent;
    @ViewChild('retrieveByIdFail', { static: true }) retrieveByIdFail: AlertDialogComponent;
    @ViewChild('results', { static: true }) results: BucketActionSummaryDialogComponent;
    @ViewChild('createCarouselPrompt', { static: true }) createCarouselPrompt: PromptDialogComponent;
    @ViewChild('createCarouselFail', { static: true }) createCarouselFail: AlertDialogComponent;
    @ViewChild('importDialog') importDialog: RecordBucketItemUploadDialogComponent;
    @ViewChild('exportDialog') exportDialog: RecordBucketExportDialogComponent;
    containerDeletionResultMap = {};

    catSearchQuery: string;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private cdr: ChangeDetectorRef,
        private auth: AuthService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private net: NetService,
        private evt: EventService,
        private flatData: GridFlatDataService,
        private bucketService: RecordBucketService,
        private stateService: RecordBucketStateService
    ) {}

    async ngOnInit() {
        this.initInProgress = true;
        console.debug('RecordBucketComponent: this', this);

        this.route.url.pipe(takeUntil(this.destroy$)).subscribe(segments => {
            console.debug('segments', segments);
            if (segments.length > 0) {
                const datasource = this.stateService.mapUrlToDatasource(segments[0].path);
                if (datasource === 'retrieved_by_id') {
                    this.bucketIdToRetrieve = parseInt(segments[0].path, 10);
                    this.stateService.bucketIdToRetrieve = this.bucketIdToRetrieve;
                }
                this.switchTo(datasource);
            } else {
                this.switchTo('user');
            }
        });

        this.cellTextGenerator = {
            name: row => row.name,
            favorite: row => row.favorite,
            'row-actions': row => null
        };
        
        this.initDataSource();
        this.gridSelectionChange([]);
        this.grid.onRowActivate.subscribe(
            (bucket: any) => {
                this.jumpToBucketContent(bucket.id);
            }
        );
        
        await this.bucketService.loadFavoriteRecordBucketFlags(this.auth.user().id());
        this.initInProgress = false;
        this.updateCounts();
    }

    get views() {
        return this.stateService.views;
    }
    
    get currentView() {
        return this.stateService.currentView;
    }
    
    get favoriteIds() {
        return this.stateService.favoriteIds;
    }
    
    get countInProgress() {
        return this.stateService.countInProgress;
    }

    gridSelectionChange(keys: string[]) {
        this.updateSelectionState(keys);
    }

    updateSelectionState(keys: string[]) {
        this.noSelectedRows = (keys.length === 0);
        this.oneSelectedRow = (keys.length === 1);
    }

    initDataSource() {
        this.dataSource = new GridDataSource();
        this.dataSource.getRows = (pager: Pager, sort: any[]): Observable<any> => {
            console.debug('getRows, pager', pager);
            console.debug('getRows, sort', sort);
            return from(this.stateService.views[this.stateService.currentView].bucketIdQuery(pager, sort, false)).pipe(
                switchMap(response => {
                    if (response.bucketIds.length === 0) {
                        return EMPTY;
                    }
                    const query = this.stateService.buildRetrieveByIdsQuery(response.bucketIds, this.dataSource.filters);

                    // Pre-fetch all count stats
                    return this.bucketService.getRecordBucketCountStats(response.bucketIds).pipe(
                        switchMap(countStats => {
                            return this.flatData.getRows(this.grid.context, query, new Pager(), sort).pipe(
                                map(row => {
                                    return {
                                        ...row,
                                        item_count: countStats[row.id]?.item_count || 0,
                                        org_share_count: countStats[row.id]?.org_share_count || 0,
                                        usr_view_share_count: countStats[row.id]?.usr_view_share_count || 0,
                                        usr_edit_share_count: countStats[row.id]?.usr_update_share_count || 0,
                                        favorite: this.bucketService.isFavoriteRecordBucket(row.id)
                                    };
                                })
                            );
                        })
                    );
                }),
                catchError((error: unknown) => {
                    console.error('Error in getRows:', error);
                    return EMPTY;
                })
            );
        };
    }

    getViewKeys(): string[] {
        return this.stateService.getViewKeys();
    }

    isCurrentView(view: string): boolean {
        return this.stateService.isCurrentView(view);
    }

    async updateCounts() {
        if (this.initInProgress) { return; }
        await this.stateService.updateCounts();
        this.cdr.detectChanges();
    }

    switchTo(source: string) {
        console.debug('switchTo', source);
        this.stateService.navigateTo(source, this.route);
        if (!this.initInProgress) {
            this.grid.reload();
            this.updateCounts();
        }
    }

    searchCatalog(): void {
        if (!this.catSearchQuery) { return; }

        const url = this.router.serializeUrl(
            this.router.createUrlTree(
                ['/eg2/staff/catalog/search'],
                {queryParams: {query : this.catSearchQuery}}
            )
        ).toString();

        window.open(url, '_blank');
    }

    retrieveBucketById() {
        if (!this.bucketIdToRetrieve) { return; }
        this.stateService.bucketIdToRetrieve = this.bucketIdToRetrieve;
        if (this.jumpToContentsOnRetrieveById) {
            this.jumpToBucketContent(this.bucketIdToRetrieve);
        } else {
            this.switchTo('retrieved_by_id');
        }
    }

    testReferencedBucket(bucketId: number, callback: Function) {
        this.pcrud.search('cbreb', { id: bucketId }).subscribe({
            next: (response) => {
                const evt = this.evt.parse(response);
                if (evt) {
                    console.error(evt.toString());
                    this.retrieveByIdFail.dialogBody = evt.toString();
                    this.retrieveByIdFail.open();
                } else {
                    callback(response);
                }
            },
            error: (response: unknown) => {
                console.error(response);
                this.retrieveByIdFail.open();
            },
            complete: () => {
                console.debug('testReferencedBucket complete');
            }
        });
    }

    jumpToBucketContent(bucketId: number) {
        this.testReferencedBucket(bucketId, (response) => {
            console.debug('response', response);
            this.router.navigate(['content', bucketId], { relativeTo: this.route.parent, queryParams: {returnTo: this.currentView} });
        });
    }

    openTransferDialog = async (rows: any[]) => {
        if (!rows || rows.length === 0) {
            console.warn('No rows selected for transfer');
            return;
        }

        console.debug('rows', rows);
        this.transferDialog.containerObjects = rows;

        try {
            const dialogRef$ = this.transferDialog.open({size: 'lg'}).pipe(
                take(1),
                catchError((error: unknown) => {
                    console.debug('openTransferDialog, error', error);
                    return EMPTY;
                }),
                takeUntil(this.destroy$),
            );

            const result = await firstValueFrom(dialogRef$);
            console.log('Transfer owner results:', result);

            setTimeout(() => {
                this.grid.reload(); // race conditions abound, but operator change surprised me
                this.updateCounts();
            }, 1000);

        } catch (error) {
            console.error('openTransferDialog error', error);
        }
    };

    openShareBucketDialog = async (rows: any[]) => {
        if (!rows || rows.length === 0) {
            console.warn('No rows selected for sharing');
            return;
        }

        console.debug('rows', rows);
        this.shareBucketDialog.containerObjects = rows;
        this.shareBucketDialog.containerObjects = rows;
        this.shareBucketDialog.loadAouTree();
        this.shareBucketDialog.populateCheckedNodes();
        await this.shareBucketDialog.loadAuGridViewPermGrid();
        await this.shareBucketDialog.loadAuGridEditPermGrid();

        try {
            const dialogRef$ = this.shareBucketDialog.open({size: 'lg'}).pipe(
                take(1),
                catchError((error: unknown) => {
                    console.debug('openShareBucketDialog, error', error);
                    return EMPTY;
                }),
                takeUntil(this.destroy$),
            );

            const result = await firstValueFrom(dialogRef$);
            console.log('shareBucket results:', result);

            setTimeout(() => {
                this.grid.reload(); // race conditions abound, but operator change surprised me
                this.updateCounts();
            }, 1000);

        } catch (error) {
            console.error('openShareBucketDialog error', error);
        }
    };

    openDeleteBucketDialog = async (rows: any[]) => {
        if (!rows || rows.length === 0) {
            console.warn('No rows selected for deletion');
            return;
        }
        console.debug('rows', rows);

        const performDelete = async (override = false): Promise<number> => {
            const method = override
                ? 'open-ils.actor.containers.full_delete.override'
                : 'open-ils.actor.containers.full_delete';

            return new Promise((resolve, reject) => {
                this.net.request(
                    'open-ils.actor',
                    method,
                    this.auth.token(),
                    'biblio',
                    rows.map(r => r.id)
                ).pipe(
                    take(1),
                    takeUntil(this.destroy$)
                ).subscribe({
                    next: (response) => {
                        const evt = this.evt.parse(response);
                        if (evt) {
                            console.error(evt.toString());
                            this.deleteFail.dialogBody = evt.toString();
                            this.deleteFail.open();
                            resolve(0);
                        } else {
                            let carousels = 0;
                            Object.entries(response).forEach(([id, result2]) => {
                                let pass_or_fail = $localize`Deleted`;
                                const evt2 = this.evt.parse(result2);
                                if (evt2) {
                                    pass_or_fail = evt2.toString();
                                    if (evt2.textcode === 'BUCKET_LINKED_TO_CAROUSEL') {
                                        carousels++;
                                    }
                                }
                                this.containerDeletionResultMap[id] = pass_or_fail;
                            });
                            console.debug(this.containerDeletionResultMap);
                            resolve(carousels);
                        }
                    },
                    error: (error: unknown) => {
                        console.error(error);
                        this.deleteFail.dialogBody = error.toString();
                        this.deleteFail.open();
                        reject(error);
                    },
                    complete: () => {
                        this.grid.reload();
                        this.updateCounts();
                    }
                });
            });
        };

        try {
            // Initial delete confirmation
            this.deleteDialog.dialogBody = rows.map(r => r.id || '').join(', ');
            const deleteConfirmed = await firstValueFrom(this.deleteDialog.open().pipe(
                defaultIfEmpty(false),
                catchError(() => EMPTY)
            ));

            if (!deleteConfirmed) {
                console.debug('Deletion cancelled by user');
                return;
            }

            this.containerDeletionResultMap = {};
            let carouselsCount = await performDelete();
            console.debug('carouselsCount', carouselsCount);

            // Show results of initial deletion
            await firstValueFrom(this.results.open(rows, this.containerDeletionResultMap).pipe(
                defaultIfEmpty(null),
                catchError(() => EMPTY)
            ));

            if (carouselsCount > 0) {
                // Prompt for carousel override
                const overrideConfirmed = await firstValueFrom(this.deleteCarouselDialog.open().pipe(
                    defaultIfEmpty(false),
                    catchError(() => EMPTY)
                ));

                if (overrideConfirmed) {
                    carouselsCount = await performDelete(true);

                    // Show results of override deletion
                    await firstValueFrom(this.results.open(rows, this.containerDeletionResultMap).pipe(
                        defaultIfEmpty(null),
                        catchError(() => EMPTY)
                    ));
                }
            }

            console.log('Final deletion results:', this.containerDeletionResultMap);
            this.grid.reload();
            this.updateCounts();
        } catch (error) {
            console.error('openDeleteBucketDialog error:', error);
        }
    };

    openNewBucketDialog = async (rows: any[]) => {
        this.newBucketDialog.bucketClass = 'biblio';

        try {
            const dialogObservable = this.newBucketDialog.open({size: 'lg'}).pipe(
                catchError((error: unknown) => {
                    console.debug('Error in dialog observable; this can happen if we close() with no arguments:', error);
                    return EMPTY;
                }),
                takeUntil(this.destroy$),
            );

            const results = await lastValueFrom(dialogObservable, { defaultValue: null });
            console.debug('New bucket results:', results);

            this.grid.reload();
            this.updateCounts();

        } catch (error) {
            console.error('Error in new bucket dialog:', error);
        }
    };

    openEditBucketDialog = async (rows: any[]) => {
        console.debug('edit bucket',rows);
        if (!rows.length) { return; }
        const bucket = rows[0];
        this.editDialog.mode = 'update';
        this.editDialog.recordId = bucket.id;
        this.editDialog.open()

            .subscribe(ok => this.grid.reload());
    };

    async uploadRecords(rows: any[]): Promise<void> {
        if (!rows.length) { return; }
        this.importDialog.containerObjects = rows;
        this.importDialog.bucketLabel = '#' + rows[0].id + ' ' + rows[0].name;
        await lastValueFrom( this.importDialog.open({}) );
        setTimeout(() => {
            this.grid.reload();
        }, 1000);
    }

    async exportAllRecords(rows: any[]): Promise<void> {
        if (!rows.length) { return; }
        const options = await lastValueFrom(this.exportDialog.open({}));
        if (options) {
            let url = '/exporter?';
            const idParams = rows.map(row => `containerid=${encodeURIComponent(row.id)}`).join('&');
            url += idParams;
            if (options.format) { url += `&format=${encodeURIComponent(options.format)}`; }
            if (options.encoding) { url += `&encoding=${encodeURIComponent(options.encoding)}`; }
            if (options.holdings) { url += '&holdings=1'; }
            url += `&ses=${encodeURIComponent(this.auth.token())}`;
            window.open(url, '_blank');
        }
    }

    openCreateCarouselDialog = async (rows: any[]) => {
        console.debug('create carousel',rows);
        if (!rows.length) { return; }
        const bucket = rows[0];

        this.createCarouselPrompt.open({ size: 'lg' }).subscribe({
            next: (name: string) => {
                if (name && name.trim()) {
                    this.createCarousel(name.trim(), bucket);
                }
            },
            error: (e: unknown) => console.error('openCreateCarouselDialog error:', e),
            complete: () => console.debug('openCreateCarouselDialog closed')
        });
    };

    createCarousel(name: string, bucket: any) {
        this.net.request(
            'open-ils.actor',
            'open-ils.actor.carousel.create.from_bucket',
            this.auth.token(),
            name,
            bucket.id
        ).subscribe({
            next: (carouselId: number) => {
                const evt = this.evt.parse(carouselId);
                if (evt) {
                    console.error(evt.toString());
                    this.createCarouselFail.dialogBody = evt.toString();
                    this.createCarouselFail.open();
                } else {
                    this.router.navigate(['/staff/admin/local/container/carousel']);
                }
            },
            error: (error: unknown) => {
                console.error('Error creating carousel:', error);
                this.createCarouselFail.dialogBody = error.toString();
                this.createCarouselFail.open();
            }
        });
    }

    marcBatchEdit = async (rows: any[]) => {
        console.debug('marcBatchEdit',rows);
        if (!rows.length) { return; }
        this.router.navigate(['/staff/cat/marcbatch/bucket/',rows[0].id]);
    };

    favoriteBucket = async (rows: any[]) => {
        console.debug('favoriteBucket: rows', rows);
        if (!rows || rows.length === 0) {
            console.warn('No rows selected for favorites');
            return;
        }

        for (const row of rows) {
            if (!this.bucketService.isFavoriteRecordBucket(row.id)) {
                console.debug('row is not a favorite', row);
                try {
                    /* eslint-disable no-await-in-loop */
                    await this.bucketService.addFavoriteRecordBucketFlag(row.id, this.auth.user().id());
                    row.favorite = true;
                    console.debug('row is now a favorite', row);
                } catch (error) {
                    console.error(`Error adding favorite for bucket ${row.id}:`, error);
                }
            } else {
                console.debug('row is a favorite', row);
            }
        }

        setTimeout(() => {
            this.grid.reload();
            this.updateCounts();
        }, 1000);
    };

    unFavoriteBucket = async (rows: any[]) => {
        console.debug('unFavoriteBucket: rows', rows);
        if (!rows || rows.length === 0) {
            console.warn('No rows selected for un-favorites');
            return;
        }

        for (const row of rows) {
            if (this.bucketService.isFavoriteRecordBucket(row.id)) {
                console.debug('row is a favorite', row);
                try {
                    /* eslint-disable no-await-in-loop */
                    await this.bucketService.removeFavoriteRecordBucketFlag(row.id);
                    row.favorite = false;
                    console.debug('row is no longer a favorite', row);
                } catch (error) {
                    console.error(`Error removing favorite for bucket ${row.id}:`, error);
                }
            } else {
                console.debug('row is not a favorite', row);
            }
        }

        setTimeout(() => {
            this.grid.reload();
            this.updateCounts();
        }, 1000);
    };

    ngOnDestroy() {
        this.destroy$.next();
        this.destroy$.complete();
    }
}