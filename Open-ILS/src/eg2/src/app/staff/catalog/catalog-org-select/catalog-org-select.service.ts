import { inject, Injectable } from '@angular/core';
import { NetService } from '@eg/core/net.service';
import {Observable, of, tap} from 'rxjs';

@Injectable({
    providedIn: 'root'
})
export class CatalogOrgSelectService {

    private net = inject(NetService);
    private includeLocationGroupsCache: boolean;

    shouldIncludeLocationGroups(): Observable<boolean> {
        if (typeof this.includeLocationGroupsCache !== 'undefined') {
            return of(this.includeLocationGroupsCache);
        } else {
            return this.net.request(
                'open-ils.search', 'open-ils.search.staff.location_groups_with_orgs'
            ).pipe(tap(value => this.includeLocationGroupsCache = value));
        }
    }
}
