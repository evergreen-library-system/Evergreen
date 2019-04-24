import {Component, Input, OnInit, Host} from '@angular/core';
import {DomSanitizer, SafeUrl} from '@angular/platform-browser';
import {Pager} from '@eg/share/util/pager';
import {GridColumn, GridColumnSet, GridToolbarButton,
    GridToolbarAction, GridContext, GridDataSource} from '@eg/share/grid/grid';
import {GridColumnWidthComponent} from './grid-column-width.component';
import {GridPrintComponent} from './grid-print.component';

@Component({
  selector: 'eg-grid-toolbar',
  templateUrl: 'grid-toolbar.component.html'
})

export class GridToolbarComponent implements OnInit {

    @Input() gridContext: GridContext;
    @Input() colWidthConfig: GridColumnWidthComponent;
    @Input() gridPrinter: GridPrintComponent;

    renderedGroups: {[group: string]: boolean};

    csvExportInProgress: boolean;
    csvExportUrl: SafeUrl;
    csvExportFileName: string;

    constructor(private sanitizer: DomSanitizer) {
        this.renderedGroups = {};
    }

    ngOnInit() {
        this.sortActions();
    }

    sortActions() {
        const actions = this.gridContext.toolbarActions;

        const unGrouped = actions.filter(a => !a.group)
        .sort((a, b) => {
            return a.label < b.label ? -1 : 1;
        });

        const grouped = actions.filter(a => Boolean(a.group))
        .sort((a, b) => {
            if (a.group === b.group) {
                return a.label < b.label ? -1 : 1;
            } else {
                return a.group < b.group ? -1 : 1;
            }
        });

        // Insert group markers for rendering
        const seen: any = {};
        const grouped2: any[] = [];
        grouped.forEach(action => {
            if (!seen[action.group]) {
                seen[action.group] = true;
                const act = new GridToolbarAction();
                act.label = action.group;
                act.isGroup = true;
                grouped2.push(act);
            }
            grouped2.push(action);
        });

        this.gridContext.toolbarActions = unGrouped.concat(grouped2);
    }

    saveGridConfig() {
        // TODO: when server-side settings are supported, this operation
        // may offer to save to user/workstation OR org unit settings
        // depending on perms.

        this.gridContext.saveGridConfig().then(
            // hide the with config after saving
            ok => this.colWidthConfig.isVisible = false,
            err => console.error(`Error saving columns: ${err}`)
        );
    }

    performAction(action: GridToolbarAction) {
        const rows = this.gridContext.getSelectedRows();
        action.onClick.emit(rows);
        if (action.action) { action.action(rows); }
    }

    performButtonAction(button: GridToolbarButton) {
        const rows = this.gridContext.getSelectedRows();
        button.onClick.emit();
        if (button.action) { button.action(); }
    }

    shouldDisableAction(action: GridToolbarAction) {
        if (action.disableOnRows) {
            return action.disableOnRows(this.gridContext.getSelectedRows());
        }
        return false;
    }

    printHtml() {
        this.gridPrinter.printGrid();
    }

    generateCsvExportUrl($event) {

        if (this.csvExportInProgress) {
            // This is secondary href click handler.  Give the
            // browser a moment to start the download, then reset
            // the CSV download attributes / state.
            setTimeout(() => {
                this.csvExportUrl = null;
                this.csvExportFileName = '';
                this.csvExportInProgress = false;
               }, 500
            );
            return;
        }

        this.csvExportInProgress = true;

        // let the file name describe the grid
        this.csvExportFileName = (
            this.gridContext.persistKey || 'eg_grid_data'
        ).replace(/\s+/g, '_') + '.csv';

        this.gridContext.gridToCsv().then(csv => {
            const blob = new Blob([csv], {type : 'text/plain'});
            const win: any = window; // avoid TS errors
            this.csvExportUrl = this.sanitizer.bypassSecurityTrustUrl(
                (win.URL || win.webkitURL).createObjectURL(blob)
            );

            // Fire the 2nd click event now that the browser has
            // information on how to download the CSV file.
            setTimeout(() => $event.target.click());
        });

        $event.preventDefault();
    }
}


