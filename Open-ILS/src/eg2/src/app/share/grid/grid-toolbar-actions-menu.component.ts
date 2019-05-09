import {Component, Input, OnInit, Host} from '@angular/core';
import {GridToolbarAction, GridContext} from '@eg/share/grid/grid';

/** Models a list of toolbar action menu entries */

@Component({
  selector: 'eg-grid-toolbar-actions-menu',
  templateUrl: 'grid-toolbar-actions-menu.component.html'
})

export class GridToolbarActionsMenuComponent {

    @Input() gridContext: GridContext;

    performAction(action: GridToolbarAction) {
        if (action.isGroup || action.isSeparator) {
            return; // These don't perform actions
        }
        const rows = this.gridContext.getSelectedRows();
        action.onClick.emit(rows);
        if (action.action) { action.action(rows); }
    }

    shouldDisable(action: GridToolbarAction): boolean {
        if (action.disableOnRows) {
            return action.disableOnRows(this.gridContext.getSelectedRows());
        }
        return false;
    }
}

