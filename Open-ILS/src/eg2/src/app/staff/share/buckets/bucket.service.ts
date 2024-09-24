import {Injectable} from '@angular/core';
import {Subject, Observable, of, lastValueFrom} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
// import {ServerStoreService} from '@eg/core/server-store.service';
import {StoreService} from '@eg/core/store.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlService,IdlObject} from '@eg/core/idl.service';

@Injectable()
export class BucketService {
    maxRecentRecordBuckets = 10;
    private favoriteRecordBucketFlags: {[bucketId: number]: IdlObject} = {};

    private bibBucketsRefreshRequested = new Subject<void>();
    bibBucketsRefreshRequested$ = this.bibBucketsRefreshRequested.asObservable();

    constructor(
        private store: StoreService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private idl: IdlService,
    ) {}

    requestBibBucketsRefresh() {
        this.bibBucketsRefreshRequested.next();
    }

    async retrieveRecordBucketItems(bucketId: number, limit = 100): Promise<any[]> {
        const query: any = {
            bucket: bucketId
        };

        const options = {
            flesh: 2,
            flesh_fields: {
                cbrebi: ['target_biblio_record_entry'],
                bre: ['simple_record']
            },
            limit: limit,
            offset: 0
        };

        const items = await lastValueFrom(
            this.pcrud.search('cbrebi', query, options, { atomic: true })
        );

        return items.map(item => {
            const simple_record = item.target_biblio_record_entry().simple_record();
            return {
                id: item.id(),
                bucketId: this.idl.pkeyValue(item.bucket()),
                bibId: item.target_biblio_record_entry().id(),
                title: simple_record.title(),
                author: simple_record.author(),
            };
        });
    }

    async addBibsToRecordBucket(bucketId: number, bibIds: number[]): Promise<any> {
        this.logRecordBucket(bucketId);
        const items = [];
        bibIds.forEach(itemId => {
            const item = this.idl.create('cbrebi');
            item.bucket(bucketId);
            item.target_biblio_record_entry(itemId);
            items.push(item);
        });
        const requestObs = this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create',
            this.auth.token(),
            'biblio',
            items
        );

        return lastValueFrom(requestObs);
    }

    async removeBibsFromRecordBucket(bucketId: number, bibIds: number[]): Promise<any> {
        const requestObs = this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete.batch',
            this.auth.token(),
            'biblio_record_entry',
            bucketId,
            bibIds
        );

        return lastValueFrom(requestObs);
    }

    async retrieveRecordBuckets(bucketIds: number[]): Promise<any[]> {
        if (bucketIds.length === 0) {
            return [];
        }

        const [buckets, countStats] = await Promise.all([
            this.loadRecordBuckets(bucketIds),
            lastValueFrom(this.getRecordBucketCountStats(bucketIds))
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

        console.debug('retrieveRecordBuckets, buckets', buckets);
        console.debug('retrieveRecordBuckets, countStats', countStats);
        const bundle = buckets.map(bucket => ({
            bucket: this.idl.toHash(bucket),
            item_count: convertedCountStats[bucket.id().toString()]?.item_count || 0,
            org_share_count: convertedCountStats[bucket.id().toString()]?.org_share_count || 0,
            usr_view_share_count: convertedCountStats[bucket.id().toString()]?.usr_view_share_count || 0,
            usr_update_share_count: convertedCountStats[bucket.id().toString()]?.usr_update_share_count || 0,
            favorite: this.isFavoriteRecordBucket(bucket.id())
        }));
        console.debug('retrieveRecordBuckets, bundle', bundle);
        return bundle;
    }

    private async loadRecordBuckets(bucketIds: number[]): Promise<any[]> {
        return lastValueFrom(
            this.pcrud.search('cbreb',
                {id: bucketIds},
                {flesh: 1, flesh_fields: { cbreb: ['owner','owning_lib'] }},
                {atomic: true}
            )
        );
    }

    getRecordBucketCountStats(bucketIds: number[]): Observable<any> {
        const validBucketIds = bucketIds.filter(id => id !== -1);

        if (validBucketIds.length === 0) {
            return of({});
        }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.biblio_record_entry.count_stats.authoritative',
            this.auth.token(),
            validBucketIds
        );
    }

    async logRecordBucket(bucketId: number) {
        console.debug('logRecordBucket', bucketId);
        const recordBucketLog: number[] =
            this.store.getLocalItem('eg.record_bucket_log') || [];

        // Check if the bucketId is already in the array
        if (!recordBucketLog.includes(bucketId)) {
            // Add the new bucketId to the beginning of the array
            recordBucketLog.unshift(bucketId);

            // Trim the array if it exceeds the maximum size
            if (recordBucketLog.length > this.maxRecentRecordBuckets) {
                recordBucketLog.pop();
            }

            this.store.setLocalItem('eg.record_bucket_log', recordBucketLog);
        }
    }

    recentRecordBucketIds(): number[] {
        return this.store.getLocalItem('eg.record_bucket_log') || [];
    }

    async loadFavoriteRecordBucketFlags(userId: number) {
        const flags = (await lastValueFrom(
            this.pcrud.search('cbrebuf', { flag: 'favorite', usr: userId }, {}, { idlist: false, atomic: true })
        ));
        this.favoriteRecordBucketFlags = flags.reduce((acc, flag) => {
            acc[flag.bucket()] = flag;
            return acc;
        }, {});
        console.debug('Favorites, flags', flags);
    }

    isFavoriteRecordBucket(bucketId: number): boolean {
        return !!this.favoriteRecordBucketFlags[bucketId];
    }

    async addFavoriteRecordBucketFlag(bucketId: number, userId: number): Promise<void> {
        // eslint-disable-next-line max-len
        console.debug('addFavoriteRecordBucketFlag: bucketId, userId, favoriteRecordBucketFlags[bucketId]', bucketId, userId, this.favoriteRecordBucketFlags[bucketId]);
        if (!this.favoriteRecordBucketFlags[bucketId]) {
            const flag = this.idl.create('cbrebuf');
            flag.isnew(true);
            flag.bucket(bucketId);
            flag.usr(userId);
            flag.flag('favorite');

            try {
                const createdFlag = await lastValueFrom(this.pcrud.create(flag));
                this.favoriteRecordBucketFlags[bucketId] = createdFlag;
            } catch (error) {
                console.error(`Error adding favorite for bucket ${bucketId}:`, error);
                throw error;
            }
        } else {
            console.debug('addFavoriteRecordBucketFlag: suss');
        }
    }

    async removeFavoriteRecordBucketFlag(bucketId: number): Promise<void> {
        console.debug('removeFavorite: bucketId, favoriteRecordBucketFlags[bucketId]', bucketId, this.favoriteRecordBucketFlags[bucketId]);
        if (this.favoriteRecordBucketFlags[bucketId]) {
            try {
                await lastValueFrom(this.pcrud.remove(this.favoriteRecordBucketFlags[bucketId]));
                delete this.favoriteRecordBucketFlags[bucketId];
            } catch (error) {
                console.error(`Error removing favorite for bucket ${bucketId}:`, error);
                throw error;
            }
        } else {
            console.debug('removeFavorite: suss');
        }
    }

    getFavoriteRecordBucketIds(): number[] {
        return Object.keys(this.favoriteRecordBucketFlags).map(Number);
    }

    async checkForBibInRecordBuckets(bibId: number, bucketIds: number[]): Promise<number[]> {
        if (!bibId || bucketIds.length === 0) {
            return [];
        }

        const query = {
            target_biblio_record_entry: bibId,
            bucket: bucketIds
        };

        try {
            const results = await lastValueFrom( this.pcrud.search('cbrebi', query, {}, { atomic: true }) );
            console.debug('checkForBibInRecordBuckets, raw results', results);
            const qualifyingBucketIds: number[] = Array.from( new Set( results.map(result => result.bucket()) ) ); // deduped
            return qualifyingBucketIds;
        } catch (error) {
            console.error('Error checking bib in buckets:', error);
            return [];
        }
    }
}
