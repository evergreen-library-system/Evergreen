import {AfterViewInit, ChangeDetectorRef, Component, Input, OnInit} from '@angular/core';
import {Router} from '@angular/router';
import {DomSanitizer, SafeUrl} from '@angular/platform-browser';
import {GridToolbarButton, GridToolbarAction, GridContext} from '@eg/share/grid/grid';
import {GridPrintComponent} from './grid-print.component';
import {GridColumn} from './grid';

@Component({
    selector: 'eg-grid-toolbar',
    templateUrl: 'grid-toolbar.component.html',
    styleUrls: ['grid-toolbar.component.css']
})

export class GridToolbarComponent implements OnInit, AfterViewInit {

    @Input() gridContext: GridContext;
    @Input() gridPrinter: GridPrintComponent;
    @Input() disableSaveSettings = false;

    renderedGroups: {[group: string]: boolean} = {};

    csvExportInProgress: boolean;
    csvExportUrl: SafeUrl;
    csvExportFileName: string;

    constructor(
        private router: Router,
        private sanitizer: DomSanitizer,
        private cd: ChangeDetectorRef
    ) {}

    ngOnInit() {
        this.sortActions();
    }

    ngAfterViewInit(): void {
        this.cd.detectChanges();
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

        this.gridContext.saveGridConfig().catch(
            err => console.error(`Error saving columns: ${err}`)
        );
    }

    performButtonAction(button: GridToolbarButton) {
        const rows = this.gridContext.getSelectedRows();
        if (button.routerLink) {
            this.router.navigate([button.routerLink]);
        } else {
            button.onClick.emit(rows);
            if (button.action) { button.action(); }
        }
    }

    printHtml() {
        this.gridPrinter.printGrid();
    }

    printSelectedRows(): void {
        this.gridPrinter.printSelectedRows();
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
            }, 500 // eslint-disable-line no-magic-numbers
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

    toggleVisibility(col: GridColumn) {
        col.visible = !col.visible;
        if (this.gridContext.reloadOnColumnChange) {
            this.gridContext.reloadWithoutPagerReset();
        }
    }
}


