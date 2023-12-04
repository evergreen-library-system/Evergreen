import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {StoreService} from '@eg/core/store.service';

const HOLD_FOR_PATRON_KEY = 'eg.circ.patron_hold_target';

@Component({
    templateUrl: 'holds.component.html',
    selector: 'eg-patron-holds'
})
export class HoldsComponent {

    constructor(
        private router: Router,
        private org: OrgService,
        private net: NetService,
        private store: StoreService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    newHold() {

        this.store.setLoginSessionItem(HOLD_FOR_PATRON_KEY,
            this.context.summary.patron.card().barcode());

        this.router.navigate(['/staff/catalog/search']);
    }
}

