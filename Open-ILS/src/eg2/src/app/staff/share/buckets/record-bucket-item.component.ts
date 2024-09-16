import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {zip, of, firstValueFrom, lastValueFrom, EMPTY} from 'rxjs';
import {take, tap, map, switchMap, catchError} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';
import {IdlObject,IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridFlatDataService} from '@eg/share/grid/grid-flat-data.service';
import {Pager} from '@eg/share/util/pager';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {BucketDialogComponent} from '@eg/staff/share/buckets/bucket-dialog.component';
import {RecordBucketExportDialogComponent} from '@eg/staff/share/buckets/record-bucket-export-dialog.component';
import {RecordBucketItemUploadDialogComponent} from '@eg/staff/share/buckets/record-bucket-item-upload-dialog.component';
import {HoldTransferViaBibsDialogComponent} from '@eg/staff/share/holds/transfer-via-bibs-dialog.component';
import {BroadcastService} from '@eg/share/util/broadcast.service';

/**
 * Record bucket item grid interface
 */

@Component({
    selector: 'eg-record-bucket-item',
    templateUrl: 'record-bucket-item.component.html',
    styleUrls: ['./record-bucket-item.component.css']
})

export class RecordBucketItemComponent implements OnInit {

    @Input() bucketId: number;

    @ViewChild('grid', { static: true }) private grid: GridComponent;
    dataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;
    noSelectedRows: boolean;
    oneSelectedRow: boolean;

    @ViewChild('confirmDialog') confirmDialog: ConfirmDialogComponent;
    @ViewChild('alertDialog') alertDialog: AlertDialogComponent;
    @ViewChild('promptDialog') promptDialog: PromptDialogComponent;
    @ViewChild('addToBucketDialog') addToBucketDialog: BucketDialogComponent;
    @ViewChild('holdTransferDialog') holdTransferDialog: HoldTransferViaBibsDialogComponent;
    @ViewChild('exportDialog') exportDialog: RecordBucketExportDialogComponent;
    @ViewChild('importDialog') importDialog: RecordBucketItemUploadDialogComponent;

    catSearchQuery: string;
    bucket: IdlObject;
    returnTo: string;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private auth: AuthService,
        private net: NetService,
        private evt: EventService,
        private idl: IdlService,
        private store: StoreService,
        private pcrud: PcrudService,
        private broadcaster: BroadcastService,
        private flatData: GridFlatDataService
    ) {}

    ngOnInit() {
        console.debug('RecordBucketItemComponent: this', this);

        this.cellTextGenerator = {
            'target_biblio_record_entry.simple_record.title' : row => row['target_biblio_record_entry.simple_record.title'],
            'target_biblio_record_entry.merged_to' : row => row['target_biblio_record_entry.merged_to']
        };

        this.route.paramMap.pipe(
            switchMap((params: ParamMap) => {
                this.bucketId = +params.get('id');
                this.store.setLocalItem('eg.cat.last_record_bucket_retrieved', this.bucketId);
                this.initDataSource(this.bucketId);
                this.gridSelectionChange([]);

                return this.pcrud.retrieve('cbreb', this.bucketId);
            })
        ).subscribe({
            next: bucket => {
                console.debug('bucket', bucket);
                this.bucket = bucket;
            },
            error: (err: unknown) => {
                console.error('Error retrieving bucket', err);
            }
        });

        this.route.queryParams.subscribe(params => {
            this.returnTo = params.returnTo;
        });
    }

    gridSelectionChange(keys: string[]) {
        this.updateSelectionState(keys);
    }

    updateSelectionState(keys: string[]) {
        this.noSelectedRows = (keys.length === 0);
        this.oneSelectedRow = (keys.length === 1);
    }

    initDataSource(bucketId) {
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {

            const query: any = {};

            query['bucket'] = bucketId;

            let query_filters = [];
            Object.keys(this.dataSource.filters).forEach(key => {
                query_filters = query_filters.concat( this.dataSource.filters[key] );
            });

            if (query_filters.length > 0) {
                query['-and'] = query_filters;
            }

            // flatData isn't flattening nested objects for me, so we'll do it here for now
            return this.flatData.getRows(this.grid.context, query, pager, sort).pipe(map(row => {
                try {
                    const hash = this.idl.toHash(row, true);
                    // console.debug('row',hash);
                    return hash;
                } catch(E) {
                    console.debug('Error with idl.toHash: row, error', row, E);
                    return row;
                }
            }));
        };
    }

    searchCatalog(): void {
        if (!this.catSearchQuery) { return; }

        this.router.navigate(
            ['/staff/catalog/search'],
            {queryParams: {query : this.catSearchQuery}}
        );
    }

    async jumpToCatalog(rows: any[]): Promise<void> {
        const uniqueBibIds = [...new Set(rows.map(r => r['target_biblio_record_entry.id']))];
        const catSearchQuery = `record_list(${uniqueBibIds.join(',')}) sort(edit_date)#descending`;
        const url = this.router.serializeUrl(
            this.router.createUrlTree(
                ['/eg2/staff/catalog/search'],
                {queryParams: {query : catSearchQuery}}
            )
        ).toString();
        window.open(url, '_blank');
    }

    async openCatalogTabs(rows: any[]): Promise<void> {
        const uniqueBibIds = [...new Set(rows.map(r => r['target_biblio_record_entry.id']))];
        uniqueBibIds.forEach( id => setTimeout(() => window.open('/eg2/staff/catalog/record/' + id, '_blank') ) );
    }

    async legacyMergeRecords(rows: any[]): Promise<void> {
        const uniqueBibIds = [...new Set(rows.map(r => r['target_biblio_record_entry.id']))];
        const url = `/eg/staff/cat/bucket/record/view/${this.bucket.id()}/merge/${uniqueBibIds.join(',')}`;
        this.broadcaster.listen('eg.merge_records_in_bucket_' + this.bucket.id()).pipe(take(1)).subscribe(result => {
            console.debug('AngularJS bucket-merge result: ', result);
            if (result.success) setTimeout(() => {this.grid.reload()},0);
        });
        console.debug('legacyMergeRecords', url);
        window.open(url, '_blank');
    }

    async mergeRecords(rows: any[]): Promise<void> {
        this.legacyMergeRecords(rows);
    }

    async removeFromBucket(rows: any[]): Promise<boolean> {
        if (!rows.length) { return false; }
        const bibIds = rows.map(row => row['target_biblio_record_entry.id']);
        console.debug('removeFromBucket, rows, bibIds',rows,bibIds);
        try {
            const response = await firstValueFrom(this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.item.delete.batch',
                this.auth.token(), 'biblio_record_entry',
                this.bucket.id(), bibIds
            ));
            console.debug('removeFromBucket, response', response);
            const evt = this.evt.parse(response);
            if (evt) {
                console.error(evt.toString());
                this.alertDialog.dialogTitle = $localize`Error removing entry from bucket.`;
                this.alertDialog.dialogBody = evt.toString();
                await this.alertDialog.open();
                return false;
            }
            return true;
        } catch (err) {
            console.debug('removeFromBucket, error', err);
            return false;
        } finally {
            console.debug('removeFromBucket complete');
            setTimeout(() => {
                this.grid.reload();
            },1000);
        }
    }

    openAddToBucketDialog = async (rows: any[]): Promise<boolean> => {
        if (!rows.length) { return false; }
        this.addToBucketDialog.bucketClass = 'biblio';
        this.addToBucketDialog.itemIds = rows.map( r => r['target_biblio_record_entry.id'] );
        try {
            const dialogObservable = this.addToBucketDialog.open({size: 'lg'}).pipe(
                catchError((error: unknown) => {
                    console.error('Error in dialog observable; this can happen if we close() with no arguments:', error);
                    return EMPTY;
                })
            );
            const results = await lastValueFrom(dialogObservable, { defaultValue: null });
            console.debug('Add to bucket results:', results);
            this.grid.reload(); // only needed if adding to the same bucket we're in :-)
            return results !== null;
        } catch (error) {
            console.error('Error in add to bucket dialog:', error);
            return false;
        }
    };

    async exportAllRecords(): Promise<void> {
        const options = await lastValueFrom( this.exportDialog.open({}) );
        if (options) {
            let url = `/exporter?containerid=${this.bucket.id()}`;
            if (options.format) { url += `&format=${options.format}`; }
            if (options.encoding) { url += `&encoding=${options.encoding}`; }
            if (options.holdings) { url += '&holdings=1'; }
            url += `&ses=${this.auth.token()}`;
            window.open(url, '_blank');
        }
    }

    async exportRecords(rows: any[]): Promise<void> {
        const options = await lastValueFrom(this.exportDialog.open({}));
        if (options) {
            let url = '/exporter?';
            const idParams = rows.map(row => `id=${encodeURIComponent(row['target_biblio_record_entry.id'])}`).join('&');
            url += idParams;
            if (options.format) { url += `&format=${encodeURIComponent(options.format)}`; }
            if (options.encoding) { url += `&encoding=${encodeURIComponent(options.encoding)}`; }
            if (options.holdings) { url += '&holdings=1'; }
            url += `&ses=${encodeURIComponent(this.auth.token())}`;
            window.open(url, '_blank');
        }
    }

    async uploadRecords() {
        this.importDialog.containerObjects = [ {id: this.bucketId} ];
        this.importDialog.bucketLabel = '#' + this.bucketId + ' ' + this.bucket.name();
        await lastValueFrom( this.importDialog.open({size: 'lg'}) );
        setTimeout(() => {
            this.grid.reload();
        }, 1000);
    }

    async moveToBucket(rows: any[]): Promise<void> {
        if (!rows.length) { return; }
        try {
            const addResult = await this.openAddToBucketDialog(rows);
            if (addResult) {
                console.debug('moveToBucket: add part accomplished');
                const removeResult = await this.removeFromBucket(rows);
                if (removeResult) {
                    console.debug('moveToBucket: remove part accomplished');
                } else {
                    console.error('moveToBucket: failed to remove from original bucket');
                }
            } else {
                console.error('moveToBucket: failed to add to new bucket');
            }
        } catch(error) {
            console.error('moveToBucket, error', error);
        }
    }

    async transferTitleHolds(rows: any[]): Promise<void> {
        if (!rows.length) { return; }
        const uniqueBibIds = [...new Set(rows.map(r => r['target_biblio_record_entry.id']))];
        this.holdTransferDialog.bibIds = uniqueBibIds;
        const result = await this.holdTransferDialog.open({});
        console.debug('transferTitleHolds, result', result);
    }

    async deleteFromCatalog(rows: any[]): Promise<void> {
        this.confirmDialog.dialogTitle = $localize`Confirm Delete`;
        this.confirmDialog.dialogBody = $localize`Are you sure you want to delete these records from the catalog?`;
        this.confirmDialog.confirmString = $localize`Delete`;
        const confirmed = await firstValueFrom(this.confirmDialog.open());

        if (confirmed) {
            const promises = rows.map(row => this._deleteFromCatalog(row['target_biblio_record_entry.id']));
            const results = await Promise.all(promises);

            const failures = results
                .filter(result => this.evt.parse(result))
                .map(result => {
                    const evt = this.evt.parse(result);
                    return evt ? { recordId: evt.payload, desc: evt.desc } : null;
                })
                .filter(failure => failure !== null);

            if (failures.length) {
                this.alertDialog.dialogTitle = $localize`Error deleting from catalog`;
                this.alertDialog.dialogBody = failures.map( f => f.toString() ).join('; ');
                await this.showFailuresDialog(failures);
            }

            setTimeout(() => {
                this.grid.reload();
            },1000);
        }
    }

    private _deleteFromCatalog(bibId: number): Promise<any> {
        return firstValueFrom(this.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record_entry.delete',
            this.auth.token(),
            bibId
        ));
    }

    private async showFailuresDialog(failures: any[]): Promise<void> {
        let message = $localize`The following records could not be deleted: `;
        failures.forEach(failure => { // FIXME - move this to eg-string for better i18n
            message += $localize`Record ID` + ` ${failure.recordId}, ${failure.desc}; `;
        });
        this.alertDialog.dialogTitle = $localize`Deletion Failures`;
        this.alertDialog.dialogBody = message;
        await firstValueFrom(this.alertDialog.open());
    }
}
