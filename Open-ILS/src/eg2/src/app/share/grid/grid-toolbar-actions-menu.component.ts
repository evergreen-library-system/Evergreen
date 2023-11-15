import {Component, Input, OnInit, Host, ViewChild} from '@angular/core';
import {GridToolbarAction, GridContext} from '@eg/share/grid/grid';
import {ClipboardDialogComponent} from '@eg/share/clipboard/clipboard-dialog.component';

/** Models a list of toolbar action menu entries */

@Component({
    selector: 'eg-grid-toolbar-actions-menu',
    templateUrl: 'grid-toolbar-actions-menu.component.html'
})

export class GridToolbarActionsMenuComponent {

    @Input() gridContext: GridContext;

    @Input() viaContextMenu = false;

    @ViewChild('clipboardDialog') clipboardDialog: ClipboardDialogComponent;

    performAction(action: GridToolbarAction) {
        if (action.isGroup || action.isSeparator) {
            return; // These don't perform actions
        }
        const rows = this.gridContext.getSelectedRows();
        action.onClick.emit(rows);
        if (action.action) { action.action(rows); }
    }

    shouldDisable(action: GridToolbarAction): boolean {
        if (action.disabled) {
            return true;
        }
        if (action.disableOnRows) {
            return action.disableOnRows(this.gridContext.getSelectedRows());
        }
        return false;
    }

    openCopyToClipboard() {
        const row = this.gridContext.getSelectedRows()[0];
        if (!row) { return; }
        const values = [];
        this.gridContext.columnSet.displayColumns().forEach(col => {
            values.push({
                label: col.label,
                value: this.gridContext.getRowColumnValue(row, col)
            });
        });


        this.clipboardDialog.values = values;
        this.clipboardDialog.open({size: 'lg'}).toPromise();
    }
}

