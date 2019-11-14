import {Component, Input, Output, OnInit, AfterViewInit, EventEmitter,
    OnDestroy} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {MarcRecord} from './marcrecord';
import {MarcEditContext} from './editor-context';
import {TagTableService} from './tagtable.service';

/**
 * MARC Fixed Fields Editor Component
 */

@Component({
  selector: 'eg-fixed-fields-editor',
  templateUrl: './fixed-fields-editor.component.html'
})

export class FixedFieldsEditorComponent implements OnInit {

    @Input() context: MarcEditContext;
    get record(): MarcRecord { return this.context.record; }

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private tagTable: TagTableService
    ) {}

    ngOnInit() {}
}

