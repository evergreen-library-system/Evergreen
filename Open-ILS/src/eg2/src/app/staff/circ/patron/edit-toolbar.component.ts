import {Component, OnInit, Input, Output, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService, FieldVisibilityLevel} from './patron.service';

@Component({
  templateUrl: 'edit-toolbar.component.html',
  selector: 'eg-patron-edit-toolbar'
})
export class EditToolbarComponent implements OnInit {

    constructor(
        private org: OrgService,
        private net: NetService,
        private patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
    }

    changeFields(v: FieldVisibilityLevel) {
        this.context.editorFieldVisibilityLevel = v;
    }
}

