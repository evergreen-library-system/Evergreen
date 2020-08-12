import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronManagerService} from './patron.service';

@Component({
  templateUrl: 'edit.component.html',
  selector: 'eg-patron-edit'
})
export class EditComponent implements OnInit {

    constructor(
        private org: OrgService,
        private net: NetService,
        public patronService: PatronService,
        public context: PatronManagerService
    ) {}

    ngOnInit() {
    }
}

