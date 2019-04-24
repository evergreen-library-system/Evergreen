/**
 * Service for communicating with the server-side "anonymous" cache.
 */
import {Injectable} from '@angular/core';
import {Observable} from 'rxjs';
import {StoreService} from '@eg/core/store.service';
import {NetService} from '@eg/core/net.service';

// All anon-cache data is stored in a single blob per user session.
// Value is generated on the server with the first call to set_value
// and stored locally as a LoginSession item (cookie).

@Injectable()
export class AnonCacheService {

    constructor(private store: StoreService, private net: NetService) {}

    getItem(cacheKey: string, attr: string): Promise<any> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value', cacheKey, attr
        ).toPromise();
    }

    // Apply 'value' to field 'attr' in the object cached at 'cacheKey'.
    // If no cacheKey is provided, the server will generate one.
    // Returns a promised resolved with the cache key.
    setItem(cacheKey: string, attr: string, value: any): Promise<string> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            cacheKey, attr, value
        ).toPromise().then(key => {
            if (key) {
                return key;
            } else {
                return Promise.reject(
                    `Could not apply a value for attr=${attr} cacheKey=${key}`);
            }
        });
    }

    removeItem(cacheKey: string, attr: string): Promise<string> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            cacheKey, attr, null
        ).toPromise();
    }

    clear(cacheKey: string): Promise<string> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.delete_session', cacheKey
        ).toPromise();
    }
}


