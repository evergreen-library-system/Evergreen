import {Component, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {NgbAccordion} from '@ng-bootstrap/ng-bootstrap';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {SimpleReporterService} from './simple-reporter.service';

@Component({
    selector: 'eg-sr-field-chooser',
    styleUrls: ['./sr-field-chooser.component.css'],
    templateUrl: './sr-field-chooser.component.html'
})

export class SRFieldChooserComponent {

    @Input() fieldType = 'display';
    @Input() allFields: IdlObject[] = [];
    @Input() fieldGroups: IdlObject[] = [];
    @Input() orderByNames: string[] = [];
    @Output() orderByNamesChange = new EventEmitter<string[]>();
    @Input() selectedFields: IdlObject[] = [];
    @Output() selectedFieldsChange = new EventEmitter<IdlObject[]>();
    @Input() listFields: IdlObject[] = [];

    @ViewChild('fieldChooser', { static: false }) fieldChooser: NgbAccordion;
    @ViewChild('selectedList', { static: false }) selectedList: NgbAccordion;

    constructor(
        private idl: IdlService,
        private srSvc: SimpleReporterService
    ) {
    }

    fieldIsSelected(field: IdlObject) {
        return this.selectedFields.findIndex(el => el.name === field.name) > -1;
    }

    hideField(field: IdlObject) {
        if ( typeof field.hide_from === 'undefined' ) {
            return false;
        }
        return (field.hide_from.indexOf(this.fieldType) > -1);
    }

    toggleSelect(field: IdlObject) {
        const idx = this.selectedFields.findIndex(el => el.name === field.name);
        if ( idx > -1 ) {
            if ( field.forced_filter ) { return; } // These should just be hidden, but if not...
            this.selectedFields.splice(idx, 1);
            if ( this.fieldType === 'display' ) {
                this.orderByNames.splice(this.orderByNames.findIndex(el => el === field.name), 1);
            }
        } else {
            const f = { ...field };

            if ( this.fieldType === 'display' ) {
                f['alias'] = f.label; // can be edited
                this.orderByNames.push(f.name);
            }
            this.selectedFields.push(f);
        }

        this.selectedFieldsChange.emit(this.selectedFields);

        if ( this.fieldType === 'display' ) {
            this.orderByNamesChange.emit(this.orderByNames);
        }
    }

    updateField(field: IdlObject) {
        const idx = this.selectedFields.findIndex(el => el.name === field.name);
        this.selectedFields[idx] = field;
        this.selectedFieldsChange.emit(this.selectedFields);
    }

    moveUp(idx: number) {
        if ( idx > 0 ) { // should always be the case, but we check anyway
            const hold: IdlObject = this.selectedFields[idx - 1];
            this.selectedFields[idx - 1] = this.selectedFields[idx];
            this.selectedFields[idx] = hold;
            this.selectedFieldsChange.emit(this.selectedFields);
        }
    }

    moveDown(idx: number) {
        if ( idx < this.selectedFields.length ) { // see above comment
            const hold: IdlObject = this.selectedFields[idx + 1];
            this.selectedFields[idx + 1] = this.selectedFields[idx];
            this.selectedFields[idx] = hold;
            this.selectedFieldsChange.emit(this.selectedFields);
        }
    }

}
