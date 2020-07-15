import {AfterViewInit, Component, EventEmitter, Input, OnInit, Output} from '@angular/core';
import {FormGroup, FormControl, ValidationErrors, ValidatorFn, FormArray} from '@angular/forms';
import {MarcField, MarcRecord} from '../marcrecord';
import {TagTableService} from '../tagtable.service';

/**
 * A simplified editor for basic MARC records, which
 * does not require knowledge of MARC tags
 */

@Component({
  selector: 'eg-marc-simplified-editor',
  templateUrl: './simplified-editor.component.html'
})
export class MarcSimplifiedEditorComponent implements AfterViewInit, OnInit {

    @Input() buttonLabel: string;
    @Output() xmlRecordEvent = new EventEmitter<string>();

    fields: MarcField[] = [];
    editor: FormGroup;

    // DOM id prefix to prevent id collisions.
    idPrefix: string;

    fieldIndex = 0;
    fieldLabels: string[] = [];

    addField: (field: MarcField) => void;

    constructor(
        private tagTable: TagTableService
    ) {}

    ngOnInit() {
        // Add some randomness to the generated DOM IDs to ensure against clobbering
        this.idPrefix = 'marc-simplified-editor-' + Math.floor(Math.random() * 100000);
        this.editor = new FormGroup({});

        // Add a fieldId, and then add a new field to the array
        this.addField = (field: MarcField) => {
            field.fieldId = this.fieldIndex;
            this.fields.push(field);
            this.editor.addControl(String(this.fieldIndex), new FormControl(null, []));
            this.fieldIndex++;
        };

    }

    ngAfterViewInit() {
        this.tagTable.loadTags({marcRecordType: 'biblio', ffType: 'BKS'}).then(table => {
            this.fields.forEach((field) => {
                this.fieldLabels[field.fieldId] = table.getSubfieldLabel(field.tag, field.subfields[0][0]);
            });
        });
    }

    emitXml() {
        const record = new MarcRecord('<record xmlns="http://www.loc.gov/MARC21/slim"></record>');
        // need to add the value to field.subfields[0][1]
        this.fields.forEach((field) => {
            if (field.subfields[0][1] === '') { // Default value has not been applied
                field.subfields[0][1] = this.editor.get(String(field.fieldId)).value;
            }
        });
        record.fields = this.fields;
        this.xmlRecordEvent.emit(record.toXml());
    }

}


