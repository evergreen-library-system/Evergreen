import {Component, OnInit, Input, Output, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';

export enum VisibilityLevel {
    ALL_FIELDS = 0,
    SUGGESTED_FIELDS = 1,
    REQUIRED_FIELDS = 2
}

@Component({
  templateUrl: 'edit-toolbar.component.html',
  selector: 'eg-patron-edit-toolbar'
})
export class EditToolbarComponent implements OnInit {

    disableSave = false;
    visibilityLevel: VisibilityLevel = VisibilityLevel.ALL_FIELDS;

    disableSaveStateChanged: EventEmitter<boolean> = new EventEmitter<boolean>();

    saveClicked: EventEmitter<void> = new EventEmitter<void>();
    saveCloneClicked: EventEmitter<void> = new EventEmitter<void>();
    printClicked: EventEmitter<void> = new EventEmitter<void>();

    constructor(
        private org: OrgService,
        private net: NetService,
        private patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
        // Emitted by our editor component.
        this.disableSaveStateChanged.subscribe(d => this.disableSave = d);
    }

    changeFields(v: VisibilityLevel) {
        this.visibilityLevel = v;
    }
}

