import {Component, Input, OnInit, Host} from '@angular/core';
import {GridToolbarAction, GridContext} from '@eg/share/grid/grid';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

/** Allows users to show/hide toolbar action entries */

@Component({
    selector: 'eg-grid-toolbar-actions-editor',
    templateUrl: 'grid-toolbar-actions-editor.component.html'
})

export class GridToolbarActionsEditorComponent extends DialogComponent {

    @Input() gridContext: GridContext;

    showHideClicked(action: GridToolbarAction) {
        action.hidden = !action.hidden;

        if (!action.group) { return; }

        // When hiding the last entry in a group, hide the group as well.

        const group = this.gridContext.toolbarActions
            .filter(entry => entry.isGroup && entry.label === action.group)[0];

        const visibles = this.gridContext.toolbarActions
            .filter(a => a.group === action.group && !a.hidden);

        group.hidden = visibles.length === 0;
    }
}

