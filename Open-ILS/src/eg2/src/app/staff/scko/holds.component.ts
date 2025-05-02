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
    templateUrl: 'holds.component.html'
})

export class SckoHoldsComponent implements OnInit {

    holds: IdlObject[] = [];

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
            this.router.navigate(['/staff/selfcheck']);
            return;
        }

        this.scko.resetPatronTimeout();

        const orderBy = [
            {shelf_time: {nulls: 'last'}},
            {capture_time: {nulls: 'last'}},
            {request_time: {nulls: 'last'}}
        ];

        const filters = {
            usr_id: this.scko.patronSummary.id,
            fulfillment_time: null,
            cancel_time: null
        };

        let first = true;
        this.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.wide_hash.stream',
            this.auth.token(), filters, orderBy, 1000, 0, {}
        ).subscribe(holdData => {

            if (first) { // First response is the hold count.
                first = false;
                return;
            }

            this.holds.push(holdData);
        });
    }

    printList() {
        this.printer.print({
            templateName: 'scko_holds',
            contextData: {
                holds: this.holds,
                user: this.scko.patronSummary.patron
            },
            printContext: 'default'
        });
    }
}


