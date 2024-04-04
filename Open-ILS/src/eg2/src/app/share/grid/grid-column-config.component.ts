import {Component, Input, OnInit} from '@angular/core';
import {Observable} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {GridColumn, GridColumnSet, GridContext} from './grid';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'eg-grid-column-config',
    templateUrl: './grid-column-config.component.html',
    styleUrls: ['./grid-column-config.component.css']
})

/**
 */
export class GridColumnConfigComponent extends DialogComponent implements OnInit {
    @Input() gridContext: GridContext;
    columnSet: GridColumnSet;
    dragRow: GridColumn = null;
    dragStart: number = null;
    moveSelector: string = null;
    changesPending = false;

    open(ops: NgbModalOptions): Observable<any> {
        this.changesPending = false;
        this.columnSet = this.gridContext.columnSet;
        return super.open(ops);
    }

    toggleVisibility(col: GridColumn) {
        col.visible = !col.visible;
        this.changesPending = true;
    }

    // Avoid reloading on each column change and instead reload the
    // data if needed after all changes are complete.
    // Override close() so we can reload data if needed.
    // NOTE: ng-bootstrap v 8.0.0 has a 'closed' emitter, but
    // we're not there yet.
    close(value?: any) {
        if (this.modalRef) { this.modalRef.close(); }
        this.finalize();

        if (this.changesPending && this.gridContext.reloadOnColumnChange) {
            this.gridContext.reloadWithoutPagerReset();
        }
    }

    onRowDragStart($event, col: GridColumn) {
        this.dragRow = col;
        this.dragStart = $event.target.closest('tr').sectionRowIndex;
        this.moveSelector = '#move-btn-' + col.name;
        // console.debug("Starting from: ", this.dragStart);
    }

    onRowDragEnter($event) {
        $event.target.closest('tr').classList.add('active');
        $event.preventDefault();
    }

    onRowDragLeave($event) {
        // console.debug("Leaving: ", $event.target.closest('tr'));
        $event.target.closest('tr').classList.remove('active');
        $event.preventDefault();
    }

    onRowDrop($event) {
        const targetRow = $event.target.closest('tr');
        targetRow.classList.remove('active');
        $event.preventDefault();

        let targetRowIndex = targetRow.sectionRowIndex;

        if (targetRowIndex === this.dragStart) {return;}

        if (targetRow.id === 'dropzone-start') {
            targetRowIndex = 0;
        }

        this.gridContext.columnSet.columns.splice(targetRowIndex, 0, this.gridContext.columnSet.columns.splice(this.dragStart, 1)[0]);

        // focus back on the Move button of the dragged row
        this.setFocusAfterMove();

        this.dragRow = null;
        this.dragStart = null;
    }

    moveColumn(col: GridColumn, diff: number) {
        this.gridContext.columnSet.moveColumn(col, diff);
        this.moveSelector = '#move-btn-' + col.name;
        this.setFocusAfterMove();
    }

    setFocusAfterMove() {
        setTimeout(() => {
            const el = document.querySelector(this.moveSelector) as HTMLElement;
            el.focus();
        });
    }

    saveGridConfig() {
        this.gridContext.saveGridConfig();
        this.close();
    }
}


