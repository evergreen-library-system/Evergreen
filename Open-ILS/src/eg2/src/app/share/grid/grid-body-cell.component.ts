import {Component, Input, OnInit, AfterViewInit,
    TemplateRef, ElementRef} from '@angular/core';
import {GridContext, GridColumn, GridRowSelector,
    GridColumnSet, GridDataSource} from './grid';

@Component({
  selector: 'eg-grid-body-cell',
  templateUrl: './grid-body-cell.component.html'
})

export class GridBodyCellComponent implements OnInit {

    @Input() context: GridContext;
    @Input() row: any;
    @Input() column: GridColumn;

    initDone: boolean;

    constructor(
        private elm: ElementRef
    ) {}

    ngOnInit() {}
}

