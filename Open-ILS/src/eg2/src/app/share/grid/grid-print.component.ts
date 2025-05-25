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
            { next: row => {
                this.progressDialog.increment();
                textItems.rows.push(row);
            }, error: (err: unknown) => this.progressDialog.close(), complete: ()  => {
                this.progressDialog.close();
                this.printer.print({
                    template: this.printTemplate,
                    contextData: textItems,
                    printContext: 'default'
                });
            } }
        );
    }

    printSelectedRows(): void {
        const columns = this.gridContext.columnSet.displayColumns();
        const rows = this.gridContext.rowSelector.selected()
            .reduce<{text: any; pos: number}[]>((pairs, index) => {
                const pos = this.gridContext.getRowPosition(index);
                if (pos === undefined) {return pairs;}

                const row = this.gridContext.dataSource.data[pos];
                if (row === undefined) {return pairs;}

                const text = this.gridContext.getRowAsFlatText(row);
                return pairs.concat({text, pos});
            }, [])
            .sort(({pos: a}, {pos: b}) => a - b)
            .map(({text}) => text);

        this.printer.print({
            template: this.printTemplate,
            contextData: {columns, rows},
            printContext: 'default'
        });
    }
}


