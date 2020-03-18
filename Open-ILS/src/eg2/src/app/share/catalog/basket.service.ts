import {Injectable, EventEmitter} from '@angular/core';
import {Observable} from 'rxjs';
import {StoreService} from '@eg/core/store.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';

// Baskets are stored in an anonymous cache using the cache key stored
// in a LoginSessionItem (i.e. cookie) at name BASKET_CACHE_KEY_COOKIE.
// The list is stored under attribute BASKET_CACHE_ATTR.
// Avoid conflicts with the AngularJS embedded catalog basket by
// using a different value for the cookie name, since our version
// stores all cookies as JSON, unlike the TPAC.
const BASKET_CACHE_KEY_COOKIE = 'basket';
const BASKET_CACHE_ATTR = 'recordIds';

@Injectable()
export class BasketService {

    idList: number[];

    // Fired every time our list of ID's are updated.
    onChange: EventEmitter<number[]>;

    constructor(
        private net: NetService,
        private pcrud: PcrudService,
        private store: StoreService,
        private anonCache: AnonCacheService
    ) {
        this.idList = [];
        this.onChange = new EventEmitter<number[]>();

        // Tell the browser store service to clear the basket on logout.
        this.store.addLoginSessionKey(BASKET_CACHE_KEY_COOKIE);
    }

    hasRecordId(id: number): boolean {
        return this.idList.indexOf(Number(id)) > -1;
    }

    recordCount(): number {
        return this.idList.length;
    }

    // TODO: Add server-side API for sorting a set of bibs by ID.
    // See EGCatLoader/Container::fetch_mylist
    getRecordIds(): Promise<number[]> {
        const cacheKey = this.store.getLoginSessionItem(BASKET_CACHE_KEY_COOKIE);
        this.idList = [];

        if (!cacheKey) { return Promise.resolve(this.idList); }

        return this.anonCache.getItem(cacheKey, BASKET_CACHE_ATTR).then(
            list => {
                if (!list) { return this.idList; }
                this.idList = list.map(id => Number(id));
                return this.idList;
            }
        );
    }

    setRecordIds(ids: number[]): Promise<number[]> {
        this.idList = ids;

        // If we have no cache key, that's OK, assume this is the first
        // attempt at adding a value and let the server create the cache
        // key for us, then store the value in our cookie.
        const cacheKey = this.store.getLoginSessionItem(BASKET_CACHE_KEY_COOKIE);

        return this.anonCache.setItem(cacheKey, BASKET_CACHE_ATTR, this.idList)
        .then(key => {
            this.store.setLoginSessionItem(BASKET_CACHE_KEY_COOKIE, key);
            this.onChange.emit(this.idList);
            return this.idList;
        });
    }

    addRecordIds(ids: number[]): Promise<number[]> {
        ids = ids.filter(id => !this.hasRecordId(id)); // avoid dupes

        if (ids.length === 0) {
            return Promise.resolve(this.idList);
        }
        return this.setRecordIds(
            this.idList.concat(ids.map(id => Number(id))));
    }

    removeRecordIds(ids: number[]): Promise<number[]> {

        if (this.idList.length === 0) {
            return Promise.resolve(this.idList);
        }

        const wantedIds = this.idList.filter(
            id => ids.indexOf(Number(id)) < 0);

        return this.setRecordIds(wantedIds); // OK if empty
    }

    removeAllRecordIds(): Promise<number[]> {
        return this.setRecordIds([]);
    }
}


