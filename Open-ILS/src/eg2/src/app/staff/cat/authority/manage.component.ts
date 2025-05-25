import {Component, OnInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {map} from 'rxjs';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Pager} from '@eg/share/util/pager';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';

/* Find, merge, and edit authority records */

@Component({
    templateUrl: 'manage.component.html',
    styles: [
        '#marcEditor { background-color: hsla(223, 25%, 91%, 1) }',
        '[data-bs-theme="dark"] #marcEditor { background-color: var(--bs-body-bg-alt) }'
    ]
})
export class ManageAuthorityComponent implements OnInit {

    authId: number;
    authTab = 'bibs';
    authMeta: any;
    linkedBibIdSource: (pager: Pager, sort: any) => Promise<number[]>;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService
    ) {
    }

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.authTab = params.get('tab') || 'bibs';
            const id = +params.get('id');

            if (id !== this.authId) {
                this.authId = id;

                this.net.request(
                    'open-ils.search',
                    'open-ils.search.authority.main_entry', this.authId
                // eslint-disable-next-line rxjs-x/no-nested-subscribe
                ).subscribe(meta => this.authMeta = meta);
            }
        });

        this.linkedBibIdSource = (pager: Pager, sort: any) => {
            return this.getLinkedBibIds(pager, sort);
        };
    }

    getLinkedBibIds(pager: Pager, sort: any): Promise<number[]> {
        const orderBy: any = {};
        if (sort.length && sort[0].name === 'id') {
            orderBy.abl = 'bib ' + sort[0].dir;
        }
        return this.pcrud.search('abl',
            {authority: this.authId},
            {limit: pager.limit, offset: pager.offset, order_by: orderBy},
            {atomic: true}
        ).pipe(map(links => links.map(l => l.bib()))
        ).toPromise();
    }

    // Changing a tab in the UI means changing the route.
    // Changing the route ultimately results in changing the tab.
    beforeNavChange(evt: NgbNavChangeEvent) {

        // prevent tab changing until after route navigation
        evt.preventDefault();

        this.authTab = evt.nextId;
        this.routeToTab();
    }

    routeToTab() {
        const url =
            `/staff/cat/authority/manage/${this.authId}/${this.authTab}`;
        this.router.navigate([url]);
    }
}


