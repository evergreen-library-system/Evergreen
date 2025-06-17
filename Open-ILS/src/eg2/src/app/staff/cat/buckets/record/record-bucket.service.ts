import {Injectable} from '@angular/core';
import {Subject, Observable} from 'rxjs';
// import {ServerStoreService} from '@eg/core/server-store.service';
import {StoreService} from '@eg/core/store.service';
import { BucketService } from '@eg/staff/share/buckets/bucket.service';

@Injectable()
export class RecordBucketService {
    maxRecentRecordBuckets = 10;

    private bibBucketsRefreshRequested = new Subject<void>();
    bibBucketsRefreshRequested$ = this.bibBucketsRefreshRequested.asObservable();

    constructor(
        private store: StoreService,
        private bucketService: BucketService
    ) {}

    requestBibBucketsRefresh() {
        this.bibBucketsRefreshRequested.next();
    }

    async retrieveRecordBucketItems(bucketId: number, limit = 100): Promise<any[]> {
        // Use the bucket service to retrieve items
        const items = await this.bucketService.retrieveBucketItems(bucketId, 'biblio', limit);
        
        // Map the items returned by the bucket service to the expected format
        return items.map(item => {
            const targetBre = item.target_biblio_record_entry || {};
            const simpleRecord = targetBre.simple_record || {};
            
            return {
                id: item.id || 0,
                bucketId: bucketId,
                bibId: targetBre.id || 0,
                title: simpleRecord.title || '',
                author: simpleRecord.author || '',
            };
        });
    }

    async addBibsToRecordBucket(bucketId: number, bibIds: number[]): Promise<any> {
        this.logRecordBucket(bucketId);
        return this.bucketService.addItemsToBucket(
            bucketId,
            bibIds,
            'biblio'
        );
    }

    async removeBibsFromRecordBucket(bucketId: number, bibIds: number[]): Promise<any> {
        return this.bucketService.removeItemsFromBucket(
            bucketId,
            bibIds,
            'biblio'
        );
    }

    async retrieveRecordBuckets(bucketIds: number[]): Promise<any[]> {
        return this.bucketService.retrieveBuckets(
            'biblio',
            bucketIds
        );
    }

    getRecordBucketCountStats(bucketIds: number[]): Observable<any> {
        return this.bucketService.getBucketCountStats(
            'biblio',
            bucketIds
        );
    }

    async logRecordBucket(bucketId: number) {
        console.debug('Logging Record Bucket: ', bucketId);
        await this.bucketService.logBucket('biblio', bucketId);
    }

    recentRecordBucketIds(): number[] {
        return this.store.getLocalItem('eg.record_bucket_log') || [];
    }

    async loadFavoriteRecordBucketFlags(userId: number) {
        await this.bucketService.loadFavoriteBucketFlags(userId, 'biblio');
    }

    isFavoriteRecordBucket(bucketId: number): boolean {
        return !!this.bucketService.getFavoriteBucketIds('biblio').find(id => id === bucketId);
    }

    async addFavoriteRecordBucketFlag(bucketId: number, userId: number): Promise<void> {
        this.bucketService.addBucketToFavorites(bucketId, 'biblio');
    }

    async removeFavoriteRecordBucketFlag(bucketId: number): Promise<void> {
        this.bucketService.removeBucketFromFavorites(bucketId, 'biblio');
    }

    getFavoriteRecordBucketIds(): number[] {
        return this.bucketService.getFavoriteBucketIds('biblio');
    }

    async checkForBibInRecordBuckets(bibId: number, bucketIds?: number[]): Promise<number[]> {
        return this.bucketService.checkForItemInBuckets(
            bibId,
            'biblio'
        );
    }
}