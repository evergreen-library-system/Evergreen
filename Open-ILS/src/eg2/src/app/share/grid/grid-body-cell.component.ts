import {Component, Input, OnInit, AfterViewInit,
    TemplateRef, ElementRef, AfterContentChecked} from '@angular/core';
import {GridContext, GridColumn, GridRowSelector,
    GridColumnSet, GridDataSource} from './grid';

@Component({
  selector: 'eg-grid-body-cell',
  templateUrl: './grid-body-cell.component.html'
})

export class GridBodyCellComponent implements OnInit, AfterContentChecked {

    @Input() context: GridContext;
    @Input() row: any;
    @Input() column: GridColumn;

    initDone: boolean;
    tooltipContent: string | TemplateRef<any>;

    constructor(
        private elm: ElementRef
    ) {}

    ngOnInit() {}

    ngAfterContentChecked() {
        this.setTooltip();
    }

    // Returns true if the contents of this cell exceed the
    // boundaries of its container.
    cellOverflows(): boolean {
        let node = this.elm.nativeElement;
        if (node) {
            node = node.parentNode;
            return node && (
                node.scrollHeight > node.clientHeight ||
                node.scrollWidth > node.clientWidth
            );
        }
        return false;
    }

    // Tooltips are only applied to cells whose contents exceed
    // their container.
    // Applying an empty string value prevents a tooltip from rendering.
    setTooltip() {
        if (this.cellOverflows()) {
            this.tooltipContent = this.column.cellTemplate ||
                this.context.getRowColumnValue(this.row, this.column);
        } else {
            // No tooltip
            this.tooltipContent = '';
        }
    }
}

