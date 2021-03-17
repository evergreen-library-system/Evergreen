import {Component, OnInit, Input, Output, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';

type FieldOptions = 'required' | 'suggested' | 'all';

@Component({
  templateUrl: 'edit-toolbar.component.html',
  selector: 'eg-patron-edit-toolbar'
})
export class EditToolbarComponent implements OnInit {

    showFields: FieldOptions = 'all';

    @Output() saveClicked: EventEmitter<void> = new EventEmitter<void>();
    @Output() saveCloneClicked: EventEmitter<void> = new EventEmitter<void>();
    @Output() printClicked: EventEmitter<void> = new EventEmitter<void>();
    @Output() showFieldsChanged:
      EventEmitter<FieldOptions> = new EventEmitter<FieldOptions>();

    constructor(
        private org: OrgService,
        private net: NetService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
    }

    changeFields(field: FieldOptions) {
        this.showFields = field;
        this.showFieldsChanged.emit(field);
    }
}

