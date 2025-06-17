import {Injectable} from '@angular/core';
import {Subject, Observable} from 'rxjs';
// import {ServerStoreService} from '@eg/core/server-store.service';
import {StoreService} from '@eg/core/store.service';
import { BucketService } from '@eg/staff/share/buckets/bucket.service';
import { BucketClass } from '@eg/staff/share/buckets/bucket-config.service';

@Injectable()
export class RecordBucketService {
    maxRecentRecordBuckets = 10;
    bucketClass: BucketClass = 'biblio';

    constructor(
        private store: StoreService,
        private bucketService: BucketService
    ) {}

    requestBibBucketsRefresh() {
        this.bucketService.requestBucketRefresh();
    }

    getBucketRefreshRequested(): Observable<void> {
        return this.bucketService.getBucketRefreshRequested();
    }

    async retrieveRecordBucketItems(bucketId: number, limit = 100): Promise<any[]> {
        // Use the bucket service to retrieve items
        const items = await this.bucketService.retrieveBucketItems(bucketId, this.bucketClass, limit);
        if (!items || items.length === 0) {
            return [];
        }
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
            this.bucketClass
        );
    }

    async removeBibsFromRecordBucket(bucketId: number, bibIds: number[]): Promise<any> {
        return this.bucketService.removeItemsFromBucket(
            bucketId,
            bibIds,
            this.bucketClass
        );
    }

    async retrieveRecordBuckets(bucketIds: number[]): Promise<any[]> {
        return this.bucketService.retrieveBuckets(
            this.bucketClass,
            bucketIds
        );
    }

    getRecordBucketCountStats(bucketIds: number[]): Observable<any> {
        return this.bucketService.getBucketCountStats(
            this.bucketClass,
            bucketIds
        );
    }

    async logRecordBucket(bucketId: number) {
        console.debug('Logging Record Bucket: ', bucketId);
        await this.bucketService.logBucket(this.bucketClass, bucketId);
    }

    recentRecordBucketIds(): number[] {
        return this.store.getLocalItem('eg.record_bucket_log') || [];
    }

    async loadFavoriteRecordBucketFlags(userId: number) {
        await this.bucketService.loadFavoriteBucketFlags(userId, this.bucketClass);
    }

    isFavoriteRecordBucket(bucketId: number): boolean {
        return !!this.bucketService.getFavoriteBucketIds(this.bucketClass).find(id => id === bucketId);
    }

    async addFavoriteRecordBucketFlag(bucketId: number, userId: number): Promise<void> {
        this.bucketService.addBucketToFavorites(bucketId, this.bucketClass);
    }

    async removeFavoriteRecordBucketFlag(bucketId: number): Promise<void> {
        this.bucketService.removeBucketFromFavorites(bucketId, this.bucketClass);
    }

    getFavoriteRecordBucketIds(): number[] {
        return this.bucketService.getFavoriteBucketIds(this.bucketClass);
    }

    async checkForBibInRecordBuckets(bibId: number, bucketIds?: number[]): Promise<number[]> {
        return this.bucketService.checkForItemInBuckets(
            bibId,
            this.bucketClass
        );
    }
}