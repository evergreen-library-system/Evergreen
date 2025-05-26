import { Injectable } from '@angular/core';
import { ServerStoreService } from '@eg/core/server-store.service';
import { concat, EMPTY, from, Observable, of, Subject } from 'rxjs';
import { catchError, concatMap, distinctUntilChanged, map, shareReplay } from 'rxjs/operators';

/**
 * Manages the workstation setting ui.staff.disable_links_newtabs.
 *
 * Note: The UI for the workstation setting is only in AngularJS,
 * so this will only load the initial setting value.
 */

type SettingValue = boolean | null;
const SETTING_KEY = 'ui.staff.disable_links_newtabs';

@Injectable({
    providedIn: 'root'
})
export class LinkTargetService {

    private readonly updates = new Subject<SettingValue>();
    private readonly updates$ = this.updates.pipe(
        concatMap(update => this.updateSetting(update))
    );

    readonly newTabsDisabled$ =
        concat(
            this.getSetting(),
            this.updates$
        ).pipe(
            map(settingValue => !!settingValue),
            distinctUntilChanged(),
            shareReplay({ bufferSize: 1, refCount: false })
        );

    constructor(private readonly store: ServerStoreService) {}

    private getSetting(): Observable<SettingValue> {
        return from(this.store.getItem(SETTING_KEY)).pipe(
            catchError(() => {
                console.error(`Failed to get ${SETTING_KEY} setting`);
                return of(null);
            })
        );
    }

    private updateSetting(update: SettingValue): Observable<SettingValue> {
        return from(this.store.setItem(SETTING_KEY, update)).pipe(
            catchError(() => {
                console.error(`Failed to set ${SETTING_KEY} setting`);
                return EMPTY;
            })
        );
    }

    disableNewTabs(): void {
        this.updates.next(true);
    }

    enableNewTabs(): void {
        this.updates.next(null);
    }
}
