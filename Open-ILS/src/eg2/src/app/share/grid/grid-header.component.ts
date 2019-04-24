import {Component, Input, OnInit} from '@angular/core';
import {GridContext, GridColumn, GridRowSelector,
    GridColumnSet, GridDataSource} from './grid';

@Component({
  selector: 'eg-grid-header',
  templateUrl: './grid-header.component.html'
})

export class GridHeaderComponent implements OnInit {

    @Input() context: GridContext;

    dragColumn: GridColumn;

    constructor() {}

    ngOnInit() {}

    onColumnDragEnter($event: any, col: any) {
        if (this.dragColumn && this.dragColumn.name !== col.name) {
            col.isDragTarget = true;
        }
        $event.preventDefault();
    }

    onColumnDragLeave($event: any, col: any) {
        col.isDragTarget = false;
        $event.preventDefault();
    }

    onColumnDrop(col: GridColumn) {
        this.context.columnSet.insertBefore(this.dragColumn, col);
        this.context.columnSet.columns.forEach(c => c.isDragTarget = false);
    }

    sortOneColumn(col: GridColumn) {
        let dir = 'ASC';
        const sort = this.context.dataSource.sort;

        if (sort.length && sort[0].name === col.name && sort[0].dir === 'ASC') {
            dir = 'DESC';
        }

        this.context.dataSource.sort = [{name: col.name, dir: dir}];

        if (this.context.useLocalSort) {
            this.context.sortLocal();
        } else {
            this.context.reload();
        }
    }

    // Returns true if the provided column is sorting in the
    // specified direction.
    isColumnSorting(col: GridColumn, dir: string): boolean {
        const sort = this.context.dataSource.sort.filter(c => c.name === col.name)[0];
        return sort && sort.dir === dir;
    }

    handleBatchSelect($event) {
        if ($event.target.checked) {
            if (this.context.rowSelector.isEmpty() || !this.allRowsAreSelected()) {
                // clear selections from other pages to avoid confusion.
                this.context.rowSelector.clear();
                this.selectAll();
            }
        } else {
            this.context.rowSelector.clear();
        }
    }

    selectAll() {
        const rows = this.context.dataSource.getPageOfRows(this.context.pager);
        const indexes = rows.map(r => this.context.getRowIndex(r));
        this.context.rowSelector.select(indexes);
    }

    allRowsAreSelected(): boolean {
        const rows = this.context.dataSource.getPageOfRows(this.context.pager);
        const indexes = rows.map(r => this.context.getRowIndex(r));
        return this.context.rowSelector.contains(indexes);
    }
}

