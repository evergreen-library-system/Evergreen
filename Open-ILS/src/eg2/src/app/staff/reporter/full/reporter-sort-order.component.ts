import { Component, Input, Output, EventEmitter, inject } from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { ReporterFieldComponent } from './reporter-field.component';

@Component({
    selector: 'eg-reporter-sort-order',
    styleUrls: ['./reporter-sort-order.component.css'],
    templateUrl: './reporter-sort-order.component.html',
    imports: [StaffCommonModule, ReporterFieldComponent]
})

export class ReporterSortOrderComponent {
    @Input() fields: IdlObject[] = [];
    @Output() fieldsChange = new EventEmitter<IdlObject[]>();
    @Input() orderByNames: string[] = [];
    @Output() orderByNamesChange = new EventEmitter<string[]>();

    updateField(field: IdlObject) {
        const idx = this.fields.findIndex(el => el.treeNodeId === field.treeNodeId);
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
            sorted.push(this.fields[this.fields.findIndex(fl => fl.treeNodeId === el)]);
        });
        return sorted;
    }

}
