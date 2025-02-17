/* eslint-disable @angular-eslint/component-selector */
import {Component, Input, Host} from '@angular/core';
import {GridContext} from './grid';
import {GridComponent} from './grid.component';
import {NgbPopover} from '@ng-bootstrap/ng-bootstrap';

@Component({
    selector: 'tbody.eg-grid-body',
    templateUrl: './grid-body.component.html'
})

export class GridBodyComponent {

    @Input() context: GridContext;

    // Track the context menus so we can manually close them
    // when another popover is opened.
    contextMenus: NgbPopover[];

    constructor(@Host() private grid: GridComponent) {
        this.contextMenus = [];
    }

    handleRowClick($event: any, row: any) {

        if (this.context.disableSelect) {
            // Avoid any appearance or click behavior when row
            // selection is disabled.
            return;
        }

        if (['a', 'button', 'input', 'select', 'summary'].includes($event.target.tagName.toLowerCase())) {
            // avoid interrupting normal interactive elements
            return;
        }

        const index = this.context.getRowIndex(row);

        if (this.context.disableMultiSelect) {
            this.context.selectOneRow(index);
        } else if ($event.ctrlKey || $event.metaKey /* mac command */) {
            this.context.toggleSelectOneRow(index);

        } else if ($event.shiftKey) {
            this.context.selectRowRange(index);

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

