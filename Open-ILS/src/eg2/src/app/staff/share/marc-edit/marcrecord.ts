import {EventEmitter} from '@angular/core';

/* Wrapper class for our external MARC21.Record JS library. */

declare var MARC21; // eslint-disable-line no-var

// MARC breaker delimiter
const DELIMITER = '$';

export interface MarcSubfield    // code, value, position
    extends Array<string|number> { 0: string; 1: string; 2: number; }

// Only contains the attributes/methods we need so far.
export interface MarcField {
    fieldId?: number;
    data?: string;
    tag?: string;
    ind1?: string;
    ind2?: string;
    subfields?: MarcSubfield[];

    // For authority validation
    authValid: boolean;
    authChecked: boolean;

    // Fields are immutable when it comes to controlfield vs.
    // data field.  Stamp the value when stamping field IDs.
    isCtrlField: boolean;

    // Used for rich editor drag and drop operations
    isDragTarget?: boolean;
    isDraggable?: boolean;

    // Fake :has(:focus), which Firefox does not do
    hasFocus?: boolean;

    indicator?: (ind: number) => any;

    // Pass-through to marcrecord.js
    isControlfield(): boolean;

    deleteExactSubfields(...subfield: MarcSubfield[]): number;
}

export class MarcRecord {

    id: number; // Database ID when known.
    deleted: boolean;
    record: any; // MARC21.Record object
    breakerText: string;

    // Let clients know some fixed field shuffling may have occured.
    // Emits the fixed field code.
    fixedFieldChange: EventEmitter<string>;

    get leader(): string {
        return this.record.leader;
    }

    set leader(l: string) {
        this.record.leader = l;
    }

    get fields(): MarcField[] {
        return this.record.fields;
    }

    set fields(f: MarcField[]) {
        this.record.fields = f;
    }

    constructor(xml?: string) {
        this.record = new MARC21.Record({marcxml: xml, delimiter: DELIMITER});
        this.breakerText = this.record.toBreaker();
        this.fixedFieldChange = new EventEmitter<string>();
    }

    toXml(): string {
        return this.record.toXmlString();
    }

    toBreaker(): string {
        return this.record.toBreaker();
    }

    recordType(): string {
        return this.record.recordType();
    }

    absorbBreakerChanges() {
        this.record = new MARC21.Record(
            {marcbreaker: this.breakerText, delimiter: DELIMITER});
        // Replacing the underlying record means regenerating the field metadata
        this.stampFieldIds();
    }

    extractFixedField(fieldCode: string): string {
        return this.record.extractFixedField(fieldCode);
    }

    isFixedFieldMultivalue(fieldCode: string): boolean {
        return this.record.isFixedFieldMultivalue(fieldCode);
    }

    setFixedField(fieldCode: string, fieldValue: string): string {
        const response = this.record.setFixedField(fieldCode, fieldValue);
        this.fixedFieldChange.emit(fieldCode);
        return response;
    }

    // Give each field an identifier so it may be referenced later.
    stampFieldIds() {
        this.fields.forEach(f => this.stampFieldId(f));
    }

    // Stamp field IDs the the initial isCtrlField state.
    stampFieldId(field: MarcField) {
        if (!field.fieldId) {
            // eslint-disable-next-line no-magic-numbers
            field.fieldId = Math.floor(Math.random() * 10000000);
        }

        if (field.isCtrlField === undefined) {
            field.isCtrlField = field.isControlfield();
        }
    }

    field(spec: string, wantArray?: boolean): MarcField | MarcField[] {
        return this.record.field(spec, wantArray);
    }

    appendFields(...newFields: MarcField[]) {
        this.record.appendFields.apply(this.record, newFields);
        this.stampFieldIds();
    }

    insertFieldsBefore(field: MarcField, ...newFields: MarcField[]) {
        this.record.insertFieldsBefore.apply(
            this.record, [field].concat(newFields));
        this.stampFieldIds();
    }

    insertFieldsAfter(field: MarcField, ...newFields: MarcField[]) {
        this.record.insertFieldsAfter.apply(
            this.record, [field].concat(newFields));
        this.stampFieldIds();
    }

    insertOrderedFields(...newFields: MarcField[]) {
        this.record.insertOrderedFields.apply(this.record, newFields);
        this.stampFieldIds();
    }

    generate008(): MarcField {
        return this.record.generate008();
    }


    deleteFields(...fields: MarcField[]) {
        this.record.deleteFields.apply(this.record, fields);
    }

    getField(id: number): MarcField {
        return this.fields.filter(f => f.fieldId === id)[0];
    }

    getPreviousField(id: number): MarcField {
        for (let idx = 0; idx < this.fields.length; idx++) {
            if (this.fields[idx].fieldId === id) {
                return this.fields[idx - 1];
            }
        }
    }

    getNextField(id: number): MarcField {
        for (let idx = 0; idx < this.fields.length; idx++) {
            if (this.fields[idx].fieldId === id) {
                return this.fields[idx + 1];
            }
        }
    }

    // Turn an field-ish object into a proper MARC.Field
    newField(props: any): MarcField {
        const field = new MARC21.Field(props);
        this.stampFieldId(field);
        return field;
    }

    cloneField(field: any): MarcField {
        const props: any = {tag: field.tag};

        if (field.isControlfield()) {
            props.data = field.data;

        } else {
            props.ind1 = field.ind1;
            props.ind2 = field.ind2;
            props.subfields = this.cloneSubfields(field.subfields);
        }

        return this.newField(props);
    }

    cloneSubfields(subfields: MarcSubfield[]): MarcSubfield[] {
        const root = [];
        subfields.forEach(sf => root.push([].concat(sf)));
        return root;
    }

    // Returns a list of values for the tag + subfield combo
    subfield(tag: string, subfield: string): string {
        return this.record.subfield(tag, subfield);
    }
}

