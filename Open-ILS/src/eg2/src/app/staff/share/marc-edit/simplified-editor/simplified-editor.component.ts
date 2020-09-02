import {AfterViewInit, Component, EventEmitter, Input, OnInit, Output} from '@angular/core';
import {FormGroup, FormControl} from '@angular/forms';
import {MarcField, MarcRecord} from '../marcrecord';
import {TagTableService} from '../tagtable.service';
import {NetService} from '@eg/core/net.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

const DEFAULT_RECORD_TYPE = 'BKS';

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
    @Input() defaultMarcForm: string;

    fields: MarcField[] = [];
    editor: FormGroup;
    marcForms: ComboboxEntry[];
    marcTypes: ComboboxEntry[];

    // DOM id prefix to prevent id collisions.
    idPrefix: string;

    fieldIndex = 0;
    subfieldLabels = {};

    addField: (field: MarcField) => void;

    editorFieldIdentifier: (field: MarcField, subfield: Array<any>) => string;

    constructor(
        private net: NetService,
        private tagTable: TagTableService
    ) {}

    ngOnInit() {
        // Add some randomness to the generated DOM IDs to ensure against clobbering
        this.idPrefix = 'marc-simplified-editor-' + Math.floor(Math.random() * 100000);
        this.editor = new FormGroup({
            marcForm: new FormControl(),
            marcType: new FormControl()
        });

        // Add a fieldId, and then add a new field to the array
        this.addField = (field: MarcField) => {
            field.fieldId = this.fieldIndex;
            this.fields.push(field);
            field.subfields.forEach((subfield) => {
                this.editor.addControl(this.editorFieldIdentifier(field, subfield), new FormControl(null, []));
            });
            this.fieldIndex++;
        };

        this.editorFieldIdentifier = (field: MarcField, subfield: Array<any>) => {
            return field.tag + subfield[0]; // e.g. 245a
        };

        this.net.request('open-ils.cat',
            'open-ils.cat.biblio.fixed_field_values.by_rec_type',
            DEFAULT_RECORD_TYPE, 'Form')
            .subscribe((forms) => {
                this.marcForms = forms['Form'].map((form) => {
                    return {id: form[0], label: form[1]};
                });
            });

        this.net.request('open-ils.cat',
            'open-ils.cat.biblio.fixed_field_values.by_rec_type',
            DEFAULT_RECORD_TYPE, 'Type')
            .subscribe((types) => {
                this.marcTypes = types['Type'].map((type) => {
                    return {id: type[0], label: type[1]};
                });
            });

    }

    ngAfterViewInit() {
        this.tagTable.loadTags({marcRecordType: 'biblio', ffType: DEFAULT_RECORD_TYPE}).then(table => {
            this.fields.forEach((field) => {
                field.subfields.forEach((subfield) => {
                    this.subfieldLabels[this.editorFieldIdentifier(field, subfield)] = table.getSubfieldLabel(field.tag, subfield[0]);
                });
            });
        });
    }

    emitXml() {
        const record = new MarcRecord('<record xmlns="http://www.loc.gov/MARC21/slim"></record>');
        // need to add the value to field.subfields[0][1]
        this.fields.forEach((field) => {
            field.subfields.forEach((subfield) => {
                if (subfield[1] === '') { // Default value has not been applied
                    subfield[1] = this.editor.get(this.editorFieldIdentifier(field, subfield)).value;
                }
            });
        });
        record.fields = this.fields;

        // We need to generate an accurate 008 before setting the Form fixed field
        const field008 = record.newField({tag: '008', data: record.generate008()});
        record.insertOrderedFields(field008);

        record.setFixedField('Type', this.appropriateMarcType);
        record.setFixedField('Form', this.appropriateMarcForm);
        this.xmlRecordEvent.emit(record.toXml());
    }

    get appropriateMarcType(): string {
        return this.editor.get('marcType').value ? this.editor.get('marcType').value.id : 'a';
    }

    get appropriateMarcForm(): string {
        if (this.editor.get('marcForm').value) {
            return this.editor.get('marcForm').value.id;
        }
        return this.defaultMarcForm ? this.defaultMarcForm : ' ';
    }


}


