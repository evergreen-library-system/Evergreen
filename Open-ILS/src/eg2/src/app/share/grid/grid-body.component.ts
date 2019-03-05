import {Component, Input, OnInit, Host} from '@angular/core';
import {GridContext, GridColumn, GridRowSelector,
    GridColumnSet, GridDataSource} from './grid';
import {GridComponent} from './grid.component';

@Component({
  selector: 'eg-grid-body',
  templateUrl: './grid-body.component.html'
})

export class GridBodyComponent implements OnInit {

    @Input() context: GridContext;

    constructor(@Host() private grid: GridComponent) {}

    ngOnInit() {}

    // Not using @HostListener because it only works globally.
    onGridKeyDown(evt: KeyboardEvent) {
        switch (evt.key) {
            case 'ArrowUp':
                if (evt.shiftKey) {
                    // Extend selection up one row
                    this.context.selectMultiRowsPrevious();
                } else {
                    this.context.selectPreviousRow();
                }
                evt.stopPropagation();
                break;
            case 'ArrowDown':
                if (evt.shiftKey) {
                    // Extend selection down one row
                    this.context.selectMultiRowsNext();
                } else {
                    this.context.selectNextRow();
                }
                evt.stopPropagation();
                break;
            case 'ArrowLeft':
            case 'PageUp':
                this.context.toPrevPage()
                .then(ok => this.context.selectFirstRow(), err => {});
                evt.stopPropagation();
                break;
            case 'ArrowRight':
            case 'PageDown':
                this.context.toNextPage()
                .then(ok => this.context.selectFirstRow(), err => {});
                evt.stopPropagation();
                break;
            case 'a':
                // control-a means select all visible rows.
                // For consistency, select all rows in the current page only.
                if (evt.ctrlKey) {
                    this.context.rowSelector.clear();
                    this.context.selectRowsInPage();
                    evt.preventDefault();
                }
                break;

            case 'Enter':
                if (this.context.lastSelectedIndex) {
                    this.grid.onRowActivate.emit(
                        this.context.getRowByIndex(
                            this.context.lastSelectedIndex)
                    );
                }
                evt.stopPropagation();
                break;
        }
    }

    onRowClick($event: any, row: any, idx: number) {

        if (this.context.disableSelect) {
            // Avoid any appearance or click behavior when row
            // selection is disabled.
            return;
        }

        const index = this.context.getRowIndex(row);

        if (this.context.disableMultiSelect) {
            this.context.selectOneRow(index);
        } else if ($event.ctrlKey || $event.metaKey /* mac command */) {
            if (this.context.toggleSelectOneRow(index)) {
                this.context.lastSelectedIndex = index;
            }

        } else if ($event.shiftKey) {
            // TODO shift range click

        } else {
            this.context.selectOneRow(index);
        }

        this.grid.onRowClick.emit(row);
    }

    onRowDblClick(row: any) {
        this.grid.onRowActivate.emit(row);
    }

}

