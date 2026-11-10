import { Component, inject, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { IdlObject } from '@eg/core/idl.service';
import { RecordDisplayEntryEditComponent } from '../record-display-entry/record-display-entry-edit.component';
import { EntryMoveRequest, RecordDisplayEntryComponent } from '../record-display-entry/record-display-entry.component';
import { PcrudService } from '@eg/core/pcrud.service';

@Component({
    selector: 'eg-record-display-admin-column',
    standalone: true,
    imports: [CommonModule, RecordDisplayEntryEditComponent, RecordDisplayEntryComponent],
    templateUrl: './record-display-admin-column.component.html',
    styleUrls: ['./record-display-admin-column.component.css']
})
// This component provides an admin interface for a single
// column of a staff view component or other record display
export class RecordDisplayAdminColumnComponent {
    @Input() data: IdlObject[] = [];
    @Input() columnIndex: number;
    @Input() hasPermissions: boolean;
    @Input() type: 'search_result' | 'staff_view';
    @Output() dataChange = new EventEmitter();

    dropTarget: IdlObject;
    draggedEntry: IdlObject;

    pcrud = inject(PcrudService);

    assignNewPositions(moveFrom: number, moveTo: number) {
        if (moveTo > this.data.length) {
            moveTo = this.data.length;
        }
        this.data.splice(moveTo, 0, this.data.splice(moveFrom, 1)[0]);
        for (let i = 0; i < this.data.length; i++) {
            this.data[i].col_pos((i + 1));
        }
        this.pcrud.update(this.data).subscribe({complete: () => this.dataChange.emit(null)});
    }

    draggingInsideEntry(entry: IdlObject): boolean {
        return this.dropTarget?.id() === entry.id();
    }

    handleDrop(): void {
        // Nothing happened
        if (this.dropTarget === this.draggedEntry) {
            this.registerDropTarget(null);
            return;
        }

        if (this.draggedEntry.page_col() !== this.dropTarget.page_col()) {
            // If the entry has been dragged across columns, update
            // the column in memory
            this.draggedEntry.page_col(this.dropTarget.page_col());
        }

        const moveFrom = this.data.indexOf(this.draggedEntry);
        const moveTo = this.data.indexOf(this.dropTarget);

        this.draggedEntry = null;
        this.dropTarget = null;

        this.assignNewPositions(moveFrom, moveTo);
    }

    moveEntry(request: EntryMoveRequest): void {
        this.registerDraggedEntry(request.entry);
        this.assignNewPositions(request.oldRow, request.newRow);
    }

    registerDraggedEntry(dragged: IdlObject): void {
        this.draggedEntry = dragged;
    }

    registerDropTarget(newTarget: IdlObject): void {
        this.dropTarget = newTarget;
    }

    get maxRow(): number {
        return this.data?.reduce((leader, current) => (leader > current.col_pos()) ? leader : current.col_pos(), 1) || 1;
    }
}
