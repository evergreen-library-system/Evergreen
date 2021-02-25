import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';

@Component({
  templateUrl: 'alerts.component.html',
  selector: 'eg-patron-alerts'
})
export class PatronAlertsComponent implements OnInit {

    constructor(
        private org: OrgService,
        private net: NetService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
    }
}

