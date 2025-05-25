import {Injectable} from '@angular/core';
import {Observable, EMPTY, map, switchMap} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

/* Browse APIS and state maintenance */

@Injectable()
export class BrowseService {

    // Grid paging is disabled in this UI to support browsing in
    // both directions.  Define our own paging trackers.
    // eslint-disable-next-line no-magic-numbers
    pageSize = 15;
    searchOffset = 0;

    searchTerm: string;
    authorityAxis: string;
    authorityAxes: ComboboxEntry[];
    markedForMerge: {[id: number]: boolean} = {};

    constructor(
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService
    ) {}

    fetchAxes(): Promise<any> {
        if (this.authorityAxes) {
            return Promise.resolve(this.authorityAxes);
        }

        this.pcrud.retrieveAll('aba', {}, {atomic: true})
            .pipe(map(axes => {
                this.authorityAxes = axes
                    .map(axis => ({id: axis.code(), label: axis.name()}))
                    .sort((a1, a2) => a1.label < a2.label ? -1 : 1);
            })).toPromise();

    }

    loadAuthorities(): Observable<any> {

        if (!this.searchTerm || !this.authorityAxis) {
            return EMPTY;
        }

        return this.net.request(
            'open-ils.supercat',
            'open-ils.supercat.authority.browse.by_axis',
            this.authorityAxis, this.searchTerm,
            this.pageSize, this.searchOffset

        ).pipe(switchMap(authIds => {

            return this.net.request(
                'open-ils.search',
                'open-ils.search.authority.main_entry', authIds
            );

        })).pipe(map(authMeta => {

            const oOrg = this.org.get(authMeta.authority.owner());

            return {
                authority: authMeta.authority,
                link_count: authMeta.linked_bib_count,
                heading: authMeta.heading,
                thesaurus: authMeta.thesaurus,
                thesaurus_code: authMeta.thesaurus_code,
                owner: oOrg ? oOrg.shortname() : ''
            };
        }));
    }
}


