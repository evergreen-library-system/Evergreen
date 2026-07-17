import { Component, Input, ViewEncapsulation, inject } from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {MarcRecord} from './marcrecord';
import {MarcEditContext} from './editor-context';
import {TagTableService} from './tagtable.service';
import { CommonModule } from '@angular/common';
import { FixedFieldComponent } from './fixed-field.component';

/**
 * MARC Fixed Fields Editor Component
 */

@Component({
    selector: 'eg-fixed-fields-editor',
    templateUrl: './fixed-fields-editor.component.html',
    styleUrls: ['fixed-fields-editor.component.css'],
    encapsulation: ViewEncapsulation.None,
    imports: [
        CommonModule,
        FixedFieldComponent
    ], providers: [TagTableService]
})

export class FixedFieldsEditorComponent {
    private idl = inject(IdlService);
    private org = inject(OrgService);
    private tagTable = inject(TagTableService);


    @Input() context: MarcEditContext;
    get record(): MarcRecord { return this.context.record; }
}

