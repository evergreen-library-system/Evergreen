import { Component, EventEmitter, inject, Input, Output, ViewChild } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { RecordDisplayEntryEditComponent } from './record-display-entry-edit.component';
import { PcrudService } from '@eg/core/pcrud.service';
import { EgCommonModule } from '@eg/common.module';
import { contentTypeLabel } from './content-type';

@Component({
    // eslint-disable-next-line @angular-eslint/component-selector
    selector: 'tr[eg-record-display-entry]',
    standalone: true,
    imports: [EgCommonModule, RecordDisplayEntryEditComponent],
    templateUrl: './record-display-entry.component.html',
    styleUrls: ['record-display-entry.component.css'],
})
export class RecordDisplayEntryComponent {
    /** A curde (MARC Record Display Entry) object */
    @Input() data: IdlObject;
    @Input() hasPermissions = false;
    @Input() columnIndex: number;
    @Input() rowIndex: number;
    @Input() type: 'search_result' | 'staff_view';
    @Output() dataChange: EventEmitter<any> = new EventEmitter();
    @Output() dataMove: EventEmitter<EntryMoveRequest> = new EventEmitter();
    @ViewChild('editForm') editForm: RecordDisplayEntryEditComponent;

    pcrud = inject(PcrudService);

    delete() {
        this.pcrud.remove(this.data).subscribe({complete: () => this.dataChange.emit(null)});
    }

    edit() {
        this.editForm.open().subscribe(() => this.dataChange.emit(null));
    }

    moveUp($event: any, entry: IdlObject) {
        $event.preventDefault();
        if (this.rowIndex === 0) {
            return;
        }
        this.dataMove.emit({
            oldRow: this.rowIndex,
            newRow: this.rowIndex-1,
            entry: entry
        });
    }

    moveDown($event: any, entry: IdlObject) {
        $event.preventDefault();
        this.dataMove.emit({
            oldRow: this.rowIndex,
            newRow: this.rowIndex+1,
            entry: entry
        });
    }

    get contentType(): string {
        return contentTypeLabel(this.data.content_type());
    }

    get fieldLabel(): string {
        if (this.data?.field()?.label) { return this.data.field().label(); }
        return '';
    }
}

export interface EntryMoveRequest {
    oldRow: number;
    newRow: number;
    entry: IdlObject;
}
