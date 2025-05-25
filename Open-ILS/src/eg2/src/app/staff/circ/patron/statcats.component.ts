import {Component, Input, OnInit} from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';

@Component({
    templateUrl: 'statcats.component.html',
    selector: 'eg-patron-statcats'
})
export class PatronStatCatsComponent implements OnInit {

    @Input() patronId: number;
    catMaps: IdlObject[] = [];

    constructor(
        private router: Router,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        private patronService: PatronService,
        private context: PatronContextService
    ) {}

    ngOnInit() {

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            this.auth.token(), this.patronId, ['stat_cat_entries']).toPromise()
            .then(user => {
                const catIds = user.stat_cat_entries().map(e => e.stat_cat());
                if (catIds.length === 0) { return; }

                this.pcrud.search('actsc', {id: catIds})
                    .subscribe(cat => {
                        const map = user.stat_cat_entries()
                            .filter(e => e.stat_cat() === cat.id())[0];
                        map.stat_cat(cat);
                        cat.owner(this.org.get(cat.owner()));
                        this.catMaps.push(map);
                    });
            });
    }
}
