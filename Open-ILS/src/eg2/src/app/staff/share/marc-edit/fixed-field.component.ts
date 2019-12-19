import {Component, Input, Output, OnInit, EventEmitter} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {MarcRecord} from './marcrecord';
import {MarcEditContext} from './editor-context';
import {TagTableService} from './tagtable.service';

/**
 * MARC Fixed Field Editing Component
 */

@Component({
  selector: 'eg-fixed-field',
  templateUrl: './fixed-field.component.html',
  styleUrls: ['fixed-field.component.css']
})

export class FixedFieldComponent implements OnInit {

    @Input() fieldCode: string;
    @Input() fieldLabel: string;
    @Input() context: MarcEditContext;

    get record(): MarcRecord { return this.context.record; }

    fieldMeta: IdlObject;
    randId = Math.floor(Math.random() * 10000000);

    constructor() {}

    ngOnInit() {
        this.init().then(_ =>
            this.context.recordChange.subscribe(__ => this.init()));
    }

    init(): Promise<any> {
        if (!this.record) { return Promise.resolve(); }

        // If no field metadata is found for this fixed field code and
        // record type combo, the field will be hidden in the UI.
        return this.context.tagTable.getFfFieldMeta(this.fieldCode)
        .then(fieldMeta => this.fieldMeta = fieldMeta);
    }
}


