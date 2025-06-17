import { Injectable } from '@angular/core';
import { Subject, Observable, of, lastValueFrom } from 'rxjs';
import { map, catchError, tap } from 'rxjs/operators';
import { NetService } from '@eg/core/net.service';
import { EventService } from '@eg/core/event.service';
import { AuthService } from '@eg/core/auth.service';
// import {ServerStoreService} from '@eg/core/server-store.service';
import { StoreService } from '@eg/core/store.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { IdlService, IdlObject } from '@eg/core/idl.service';
import { BucketConfigService, BucketClass } from '@eg/staff/share/buckets/bucket-config.service';

@Injectable()
export class BucketService {
    private maxRecentBuckets = 10;
    private favoriteBucketFlags: {[bucketClass: string]: {[bucketId: number]: IdlObject}} = {};

    private bucketRefreshRequested = new Subject<void>();
    bucketRefreshRequested$ = this.bucketRefreshRequested.asObservable();

    constructor(
        private store: StoreService,
        private net: NetService,
        private auth: AuthService,
        private evt: EventService,
        private pcrud: PcrudService,
        private idl: IdlService,
        private bucketConfig: BucketConfigService,
    ) { }

    async retrieveBucketItems(bucketId: number, bucketClass: BucketClass, limit = 100): Promise<any[]> {
        return lastValueFrom(this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.contents.retrieve',
            this.auth.token(), bucketClass, bucketId
        ).pipe(
            map(resp => { const evt = this.evt.parse(resp); if (evt) throw new Error(evt.toString()); return resp || []; }),
            catchError(() => of([])),
            tap(() => this.logBucket(bucketClass, bucketId))
        ));
    }

    getBucketRefreshRequested(): Observable<void> {
        return this.bucketRefreshRequested$;
    }

    async logBucket(bucketClass: BucketClass, bucketId: number): Promise<void> {
        const storageKey = this.bucketConfig.getStorageKey(bucketClass);
        const bucketLog: number[] = this.store.getLocalItem(`${storageKey}_log`) || [];
        if (bucketLog.includes(bucketId)) { return; } // Already logged
        bucketLog.unshift(bucketId);
        if (bucketLog.length > this.maxRecentBuckets) {
            bucketLog.pop();
        }
        this.store.setLocalItem(`${storageKey}_log`, bucketLog);
    }

    async addItemsToBucket(bucketId: number, itemTargetIds: number[], bucketClass: BucketClass): Promise<any> {
        await this.logBucket(bucketClass, bucketId);
        const itemFmClass = this.bucketConfig.getBucketItemFmClass(bucketClass);
        const targetField = this.bucketConfig.getTargetField(bucketClass);
        const items = [];

        itemTargetIds.forEach(itemId => {
            const item = this.idl.create(itemFmClass);
            item.bucket(bucketId);
            item[targetField](itemId);
            items.push(item);
        });

        const requestObs = this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create',
            this.auth.token(),
            bucketClass,
            items
        );

        return lastValueFrom(requestObs);
    }

    async removeItemsFromBucket(bucketId: number, itemTargetIds: number[], bucketClass: BucketClass): Promise<any> {
        const itemFmClass = this.bucketConfig.getBucketItemFmClass(bucketClass);
        const targetField = this.bucketConfig.getTargetField(bucketClass);

        const requestObs = this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete.batch',
            this.auth.token(),
            itemFmClass,
            bucketId,
            itemTargetIds.map(id => ({ [targetField]: id }))
        );

        return lastValueFrom(requestObs);
    }

    private async loadRBuckets(bucketClass: BucketClass, bucketIds: number[]): Promise<IdlObject[]> {
        const bucketFmClass = this.bucketConfig.getBucketFmClass(bucketClass);
        return lastValueFrom(
            this.pcrud.search(
                bucketFmClass,
                { id: bucketIds },
                { flesh: 1, flesh_fields: { [bucketFmClass]: ['owner', 'owning_lib'] } },
                { atomic: true }
            )
        );
    }

    getBucketCountStats(bucketClass: BucketClass, bucketIds: number[]): Observable<any> {
        const validBucketIds = bucketIds.filter(id => id !== -1);
        if (validBucketIds.length === 0) {
            return of({});
        }
        const targetField = this.bucketConfig.getTargetField(bucketClass);
        const apiMethod = targetField.replace(/^target_/, '');
        return this.net.request(
            'open-ils.actor',
            `open-ils.actor.container.${apiMethod}.count_stats.authoritative`,
            this.auth.token(),
            validBucketIds
        ).pipe(
            map(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    throw new Error(evt.toString());
                }
                return resp;
            }),
            catchError(() => of({}))
        );
    }

    async retrieveBuckets(bucketClass: BucketClass, bucketIds: number[]): Promise<any[]> {
        if (bucketIds.length === 0) {
            return [];
        }

        const [buckets, countStats] = await Promise.all([
            this.loadRBuckets(bucketClass, bucketIds),
            lastValueFrom(this.getBucketCountStats(bucketClass, bucketIds))
        ]);

        interface CountStat {
            item_count: number;
            org_share_count: number;
            usr_view_share_count: number;
            usr_update_share_count: number;
        }

        const convertedCountStats: { [key: string]: CountStat } = Object.fromEntries(
            Object.entries(countStats).map(([key, value]) => [String(key), value as CountStat])
        );

        console.debug('retrieveBuckets, buckets', buckets);
        console.debug('retrieveBuckets, countStats', countStats);

        const bundle = buckets.map(bucket => ({
            bucket: this.idl.toHash(bucket),
            item_count: convertedCountStats[bucket.id().toString()]?.item_count || 0,
            org_share_count: convertedCountStats[bucket.id().toString()]?.org_share_count || 0,
            usr_view_share_count: convertedCountStats[bucket.id().toString()]?.usr_view_share_count || 0,
            usr_update_share_count: convertedCountStats[bucket.id().toString()]?.usr_update_share_count || 0
        }));

        console.debug('retrieveBuckets, bundle', bundle);
        return bundle;
    }

    async addBucketToFavorites(bucketId: number, bucketClass: BucketClass): Promise<void> {
        const userId = this.auth.user().id();
        const bucketFlagFmClass = this.bucketConfig.getBucketFlagFmClass(bucketClass);
        const bucketFlag = this.idl.create(bucketFlagFmClass);
        bucketFlag.isnew(true);
        bucketFlag.bucket(bucketId);
        bucketFlag.usr(userId);
        bucketFlag.flag('favorite');
        try {
            const createdFlag = await lastValueFrom(this.pcrud.create(bucketFlag));
            console.debug('addBucketToFavorites, createdFlag', createdFlag);
            
            // Initialize bucket class map if it doesn't exist yet
            if (!this.favoriteBucketFlags[bucketClass]) {
                this.favoriteBucketFlags[bucketClass] = {};
            }
            
            // Store the created flag
            this.favoriteBucketFlags[bucketClass][bucketId] = createdFlag;
            this.requestBucketRefresh();
        } catch (error) {
            console.error(`Error adding favorite for bucket ${bucketId}:`, error);
            throw error;
        }
    }

    async removeBucketFromFavorites(bucketId: number, bucketClass: BucketClass): Promise<void> {
        if (!this.favoriteBucketFlags[bucketClass] || !this.favoriteBucketFlags[bucketClass][bucketId]) {
            console.warn(`No favorite flag found for bucket ${bucketId} in class ${bucketClass}`);
            return;
        }
        try {
            await lastValueFrom(this.pcrud.remove(this.favoriteBucketFlags[bucketClass][bucketId]));
            delete this.favoriteBucketFlags[bucketClass][bucketId];
            this.requestBucketRefresh();
        } catch (error) { throw error; }
    }

    async loadFavoriteBucketFlags(userId: number, bucketClass: BucketClass): Promise<any[]> {
        const bucketFlagFmClass = this.bucketConfig.getBucketFlagFmClass(bucketClass);
        const flags = await lastValueFrom(
            this.pcrud.search(
                bucketFlagFmClass,
                { flag: 'favorite', usr: userId },
                {},
                { idlist: false, atomic: true }
            )
        );
        console.debug('loadFavoriteBucketFlags, flags', flags);
        
        // Initialize the bucket class map if needed
        if (!this.favoriteBucketFlags[bucketClass]) {
            this.favoriteBucketFlags[bucketClass] = {};
        }
        
        // Store flags in the structure and return them
        return flags.reduce((acc, flag) => {
            acc[flag.bucket()] = flag;
            this.favoriteBucketFlags[bucketClass][flag.bucket()] = flag;
            return acc;
        }, {});
    }

    getFavoriteBucketIds(bucketClass: BucketClass): number[] {
        return Object.keys(this.favoriteBucketFlags[bucketClass] || {}).map(Number);
    }

    requestBucketRefresh(): void {
        this.bucketRefreshRequested.next();
    }

    async checkForItemInBuckets(itemId: number, bucketClass: BucketClass): Promise<number[]> {
        if (!itemId) {
            return [];
        }

        const itemFmClass = this.bucketConfig.getBucketItemFmClass(bucketClass);
        const targetField = this.bucketConfig.getTargetField(bucketClass);

        const query = {
            [targetField]: itemId,
            bucket: this.getFavoriteBucketIds(bucketClass)
        };

        try {
            const results = await lastValueFrom(this.pcrud.search(itemFmClass, query, {}, { atomic: true }));
            console.debug('checkForItemInBuckets, raw results', results);
            const qualifyingBucketIds: number[] = Array.from(new Set(results.map(result => result.bucket())));
            return qualifyingBucketIds;
        } catch (error) {
            console.error('Error checking item in buckets:', error);
            return [];
        }
    }
}
