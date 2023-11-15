import {Component, Input} from '@angular/core';
import {GridContext, GridColumn} from './grid';

@Component({
    selector: 'eg-grid-body-cell',
    templateUrl: './grid-body-cell.component.html'
})

export class GridBodyCellComponent {

    @Input() context: GridContext;
    @Input() row: any;
    @Input() column: GridColumn;

    initDone: boolean;
}

