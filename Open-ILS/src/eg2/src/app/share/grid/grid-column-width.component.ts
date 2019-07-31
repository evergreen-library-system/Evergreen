import {Component, Input, OnInit} from '@angular/core';
import {GridContext, GridColumn, GridColumnSet} from './grid';

@Component({
  selector: 'eg-grid-column-width',
  templateUrl: './grid-column-width.component.html'
})

export class GridColumnWidthComponent implements OnInit {

    @Input() gridContext: GridContext;
    columnSet: GridColumnSet;
    isVisible: boolean;

    constructor() {}

    ngOnInit() {
        this.isVisible = false;
        this.columnSet = this.gridContext.columnSet;
    }

    expandColumn(col: GridColumn) {
        col.flex++;
    }

    shrinkColumn(col: GridColumn) {
        if (col.flex > 1) { col.flex--; }
    }

}

