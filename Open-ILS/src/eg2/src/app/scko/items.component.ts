import {Component, OnInit, ViewEncapsulation} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {tap} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {IdlObject} from '@eg/core/idl.service';
import {SckoService} from './scko.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PrintService} from '@eg/share/print/print.service';

@Component({
  templateUrl: 'items.component.html'
})

export class SckoItemsComponent implements OnInit {

    circs: IdlObject[] = [];

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private printer: PrintService,
        public  scko: SckoService
    ) {}

    ngOnInit() {

        if (!this.scko.patronSummary) {
            this.router.navigate(['/scko']);
            return;
        }

        this.scko.resetPatronTimeout();

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_out.authoritative',
            this.auth.token(), this.scko.patronSummary.id).toPromise()

        .then(data => {
            const ids = data.out.concat(data.overdue).concat(data.long_overdue);
            return this.scko.getFleshedCircs(ids).pipe(tap(circ => {
                this.circs.push(circ);
            })).toPromise();
        });
    }

    printList() {

        const data = this.circs.map(c => {
            return {
                circ: c,
                copy: c.target_copy(),
                title: this.scko.getCircTitle(c),
                author: this.scko.getCircAuthor(c)
            };
        });

        this.printer.print({
            templateName: 'scko_items_out',
            contextData: {
                checkouts: data,
                user: this.scko.patronSummary.patron
            },
            printContext: 'default'
        });
    }
}



