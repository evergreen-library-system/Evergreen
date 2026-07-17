import {Observable, shareReplay} from 'rxjs';

type RetrieveByKeyFn<T> = (key: string|number) => Observable<T>;

// Memoizing a function remembers its return value(s) in memory so that you can avoid repeatedly waiting for the same slow function.
// You can use this function to memoize a function that takes a single "key" argument and returns an Observable
// (e.g. retrieving a single record from OpenSRF).  It is suitable when:
//   * there will only be a limited number of possible keys,
//   * the operation is slow and/or puts load on the server, such as an OpenSRF call, and
//   * you won't be changing the values (since the old value will still be retained)
export function memoizeRetrieveByKeyFn<T>(fn: RetrieveByKeyFn<T>): RetrieveByKeyFn<T> {
    const lookup = {};
    return (key: string|number) => {
        const found = lookup[key];
        if (found) {
            return found;
        } else {
            lookup[key] = fn(key).pipe(shareReplay({bufferSize: 1, refCount: false}));
            return lookup[key];
        }
    };
}
