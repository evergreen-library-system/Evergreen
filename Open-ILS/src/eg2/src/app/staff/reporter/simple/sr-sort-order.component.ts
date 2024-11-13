import {Component, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ReporterService} from '../share/reporter.service';

@Component({
    selector: 'eg-sr-sort-order',
    styleUrls: ['./sr-sort-order.component.css'],
    templateUrl: './sr-sort-order.component.html'
})

export class SRSortOrderComponent {

    @Input() fields: IdlObject[] = [];
    @Output() fieldsChange = new EventEmitter<IdlObject[]>();
    @Input() orderByNames: string[] = [];
    @Output() orderByNamesChange = new EventEmitter<string[]>();

    constructor(
        private idl: IdlService,
        private srSvc: ReporterService
    ) {
    }

    updateField(field: IdlObject) {
        const idx = this.fields.findIndex(el => el.name === field.name);
        this.fields[idx] = field;
        this.fieldsChange.emit(this.fields);
    }

    moveDisplayUp(idx: number) {
        if ( idx > 0 ) { // should always be the case, but we check anyway
            const hold: IdlObject = this.fields[idx - 1];
            this.fields[idx - 1] = this.fields[idx];
            this.fields[idx] = hold;
            this.fieldsChange.emit(this.fields);
        }
    }

    moveDisplayDown(idx: number) {
        if ( idx < this.fields.length ) { // see above comment
            const hold: IdlObject = this.fields[idx + 1];
            this.fields[idx + 1] = this.fields[idx];
            this.fields[idx] = hold;
            this.fieldsChange.emit(this.fields);
        }
    }

    moveOrderUp(idx: number) {
        if ( idx > 0 ) {
            const hold: string = this.orderByNames[idx - 1];
            this.orderByNames[idx - 1] = this.orderByNames[idx];
            this.orderByNames[idx] = hold;
            this.orderByNamesChange.emit(this.orderByNames);
        }
    }

    moveOrderDown(idx: number) {
        if ( idx < this.orderByNames.length ) {
            const hold: string = this.orderByNames[idx + 1];
            this.orderByNames[idx + 1] = this.orderByNames[idx];
            this.orderByNames[idx] = hold;
            this.orderByNamesChange.emit(this.orderByNames);
        }
    }

    fieldsInOrderByOrder() {
        const sorted = [];
        this.orderByNames.forEach(el => {
            sorted.push(this.fields[this.fields.findIndex(fl => fl.name === el)]);
        });
        return sorted;
    }

}
