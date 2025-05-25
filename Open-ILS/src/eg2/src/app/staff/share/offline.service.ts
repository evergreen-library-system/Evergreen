import {from, concatMap} from 'rxjs';
import {Injectable} from '@angular/core';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DbStoreService} from '@eg/core/db-store.service';

/** Service for storing and fetching data related to offline services/interfaces */

const OFFLINE_CACHE_TIMEOUT = 86400000; // 1 day

@Injectable()
export class OfflineService {

    isOffline = false;

    constructor(
        private auth: AuthService,
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private db: DbStoreService
    ) {}

    refreshOfflineData(): Promise<any> {
        return this.cacheNeedsUpdating()
            .then(needs => {
                if (needs) {
                    return this.clearOfflineCache()
                        .then(_ => this.fetchOfflineData());
                }
            });
    }

    clearOfflineCache(): Promise<any> {
        return this.db.request(
            {schema: 'cache', table: 'Object', action: 'deleteAll'})

            .then(_ => this.db.request(
                {schema: 'cache', table: 'StatCat', action: 'deleteAll'})
            );
    }

    fetchOfflineData(): Promise<any> {

        // Start with the org unit list which is already loaded.
        this.addListToCache('aou', this.org.list());

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.offline.data.retrieve',
            this.auth.token()
        )
            .pipe(concatMap(data => {
                if (data.idl_class === 'actsc') {
                    return from(this.addStatCatsToCache(data.data));
                } else {
                    return from(this.addListToCache(data.idl_class, data.data));
                }
            }))
            .toPromise();
    }

    cacheNeedsUpdating(): Promise<boolean> {

        return this.db.request({
            schema: 'cache',
            table: 'CacheDate',
            action: 'selectWhereEqual',
            field: 'type',
            value: 'pgt' // most likely to have data
        }).then(rows => {
            const row = rows[0];
            if (!row) { return true; }
            return (new Date().getTime() - row.cachedate.getTime()) > OFFLINE_CACHE_TIMEOUT;
        });
    }

    addListToCache(idlClass: string, list: IdlObject[]): Promise<any> {

        const pkey = this.idl.classes[idlClass].pkey;
        const rows = list.map(item => {
            return {
                type: idlClass,
                id: '' + item[pkey](),
                object: this.idl.toHash(item)
            };
        });

        return this.db.request({
            schema: 'cache',
            table: 'Object',
            action: 'insert',
            rows: rows
        }).then(resp => {
            return this.db.request({
                schema: 'cache',
                table: 'CacheDate',
                action: 'insertOrReplace',
                rows: [{type: idlClass, cachedate: new Date()}]
            });
        });
    }

    addStatCatsToCache(statcats: IdlObject[]): Promise<any> {
        if (!statcats || statcats.length === 0) {
            return Promise.resolve();
        }

        const rows = statcats.map(
            cat => ({id: cat.id(), value: this.idl.toHash(cat)}));

        return this.db.request({
            schema: 'cache',
            table: 'StatCat',
            action: 'insert',
            rows: rows
        });
    }

    // Return promise of cache date when pending transactions exit.
    pendingXactsDate(): Promise<Date> {
        return this.db.request({
            schema: 'cache',
            table: 'CacheDate',
            action: 'selectWhereEqual',
            field: 'type',
            value: '_offlineXact'
        }).then(results => results[0] ? results[0].cachedate : null);
    }
}
