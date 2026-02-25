import { Component, OnInit, inject } from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {map} from 'rxjs';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Pager} from '@eg/share/util/pager';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { BibListComponent } from '@eg/staff/share/bib-list/bib-list.component';
import { MarcEditorComponent } from '@eg/staff/share/marc-edit/editor.component';

/* Find, merge, and edit authority records */

@Component({
    templateUrl: 'manage.component.html',
    styles: [
        '#marcEditor { background-color: hsla(223, 25%, 91%, 1) }',
        '[data-bs-theme="dark"] :host #marcEditor { background-color: var(--bs-body-bg-alt) }'
    ],
    imports: [
        BibListComponent,
        MarcEditorComponent,
        StaffCommonModule
    ]
})
export class ManageAuthorityComponent implements OnInit {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private net = inject(NetService);
    private org = inject(OrgService);
    private pcrud = inject(PcrudService);


    authId: number;
    authTab = 'bibs';
    authMeta: any;
    linkedBibIdSource: (pager: Pager, sort: any) => Promise<number[]>;

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


