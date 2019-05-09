import {Component, Input, OnInit, Host} from '@angular/core';
import {GridContext, GridColumn, GridRowSelector,
    GridToolbarAction, GridColumnSet, GridDataSource} from './grid';
import {GridComponent} from './grid.component';
import {NgbPopover} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-grid-body',
  templateUrl: './grid-body.component.html'
})

export class GridBodyComponent implements OnInit {

    @Input() context: GridContext;

    // Track the context menus so we can manually close them
    // when another popover is opened.
    contextMenus: NgbPopover[];

    constructor(@Host() private grid: GridComponent) {
        this.contextMenus = [];
    }

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

    handleRowClick($event: any, row: any) {

        if (this.context.disableSelect) {
            // Avoid any appearance or click behavior when row
            // selection is disabled.
            return;
        }

        const index = this.context.getRowIndex(row);

        if (this.context.disableMultiSelect) {
            this.context.selectOneRow(index);
        } else if ($event.ctrlKey || $event.metaKey /* mac command */) {
            this.context.toggleSelectOneRow(index);

        } else if ($event.shiftKey) {
            // TODO shift range click

        } else {
            this.context.selectOneRow(index);
        }
    }

    onRowClick($event: any, row: any, idx: number) {
        this.handleRowClick($event, row);
        this.grid.onRowClick.emit(row);
    }

    onRowDblClick(row: any) {
        this.grid.onRowActivate.emit(row);
    }

    // Apply row selection, track the new menu if needed,
    // manually close any existing open menus, open selected menu.
    onRowContextClick($event, row: any, contextMenu: NgbPopover) {
        $event.preventDefault(); // prevent browser context menu

        if (this.context.toolbarActions.length === 0) {
            // No actions to render.
            return;
        }

        if (!this.context.rowIsSelected(row)) {
            // If the focused row is not selected, select it.
            // Otherwise, avoid modifying the row selection.
            this.context.selectOneRow(this.context.getRowIndex(row));
        }

        const existing = this.contextMenus.filter(m => m === contextMenu)[0];
        if (!existing) {
            this.contextMenus.push(contextMenu);
        }

        // Force any previously opened menus to close, which does
        // not naturally occur via context-click.
        this.contextMenus.forEach(m => m.close());

        contextMenu.open({gridContext: this.context});
    }
}

