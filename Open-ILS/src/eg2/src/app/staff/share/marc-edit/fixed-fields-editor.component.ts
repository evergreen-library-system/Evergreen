import {Component, Input, ViewEncapsulation} from '@angular/core';
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
    templateUrl: './fixed-fields-editor.component.html',
    styleUrls: ['fixed-fields-editor.component.css'],
    encapsulation: ViewEncapsulation.None
})

export class FixedFieldsEditorComponent {

    @Input() context: MarcEditContext;
    get record(): MarcRecord { return this.context.record; }

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private tagTable: TagTableService
    ) {}
}

