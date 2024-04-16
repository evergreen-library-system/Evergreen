import { Injectable } from '@angular/core';
import { PcrudService } from './pcrud.service';
import { Observable, defaultIfEmpty, map, of, tap } from 'rxjs';
import { IdlObject } from './idl.service';

// This class is responsible for fetching global flag data.
// To reduce network calls, it caches values in menory until
// the user does a full page reload or otherwise re-renders the
// angular client (e.g. navigates to a legacy non-Angular screen,
// then back to an Angular screen).
@Injectable({providedIn: 'root'})
export class GlobalFlagService {
    private cache: { [key: string]: IdlObject } = {};

    constructor(private pcrud: PcrudService) { }

    retrieve(name: string): Observable<IdlObject> {
        return this.inCache(name) ? this.fromCache(name) : this.fromNetwork(name);
    }

    enabled(name: string, defaultValue?: boolean): Observable<boolean> {
        return this.retrieve(name).pipe(
            map(flag => flag.enabled() === 't'),
            defaultIfEmpty(defaultValue || false)
        );
    }

    private inCache(name: string): boolean {
        return (typeof this.cache[name] !== 'undefined');
    }

    private fromCache(name: string): Observable<IdlObject> {
        return of(this.cache[name]);
    }

    private fromNetwork(name: string): Observable<IdlObject> {
        return this.pcrud.search(
            'cgf',
            {'name': name},
            {'limit': 1}
        ).pipe(
            tap((flag: IdlObject) => this.addToCache(name, flag))
        );
    }

    private addToCache(name: string, flag: IdlObject): void {
        this.cache[name] = flag;
    }
}
