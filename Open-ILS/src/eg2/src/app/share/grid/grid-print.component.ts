import {Component, Input, TemplateRef, ViewChild} from '@angular/core';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {PrintService} from '@eg/share/print/print.service';
import {GridContext} from '@eg/share/grid/grid';

@Component({
  selector: 'eg-grid-print',
  templateUrl: './grid-print.component.html'
})

/**
 */
export class GridPrintComponent {

    @Input() gridContext: GridContext;
    @ViewChild('printTemplate', { static: true }) private printTemplate: TemplateRef<any>;
    @ViewChild('progressDialog', { static: true })
        private progressDialog: ProgressDialogComponent;

    constructor(private printer: PrintService) {}

    printGrid() {
        this.progressDialog.open();
        const columns = this.gridContext.columnSet.displayColumns();
        const textItems = {columns: columns, rows: []};

        this.gridContext.getAllRowsAsText().subscribe(
            row => {
              this.progressDialog.increment();
              textItems.rows.push(row);
            },
            err => this.progressDialog.close(),
            ()  => {
                this.progressDialog.close();
                this.printer.print({
                    template: this.printTemplate,
                    contextData: textItems,
                    printContext: 'default'
                });
            }
        );
    }
}


