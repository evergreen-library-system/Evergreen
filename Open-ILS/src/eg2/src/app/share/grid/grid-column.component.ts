import {Component, Input, OnInit, Host, TemplateRef} from '@angular/core';
import {GridColumn, GridColumnSet} from './grid';
import {GridComponent} from './grid.component';

@Component({
  selector: 'eg-grid-column',
  template: '<ng-template></ng-template>'
})

export class GridColumnComponent implements OnInit {

    // Note most input fields should match class fields for GridColumn
    @Input() name: string;
    @Input() path: string;
    @Input() label: string;
    @Input() flex: number;
    // is this the index field?
    @Input() index: boolean;

    // Columns are assumed to be visible unless hidden=true.
    @Input() hidden: boolean;

    @Input() sortable: boolean;
    @Input() datatype: string;
    @Input() multiSortable: boolean;

    // Display date and time when datatype = timestamp
    @Input() datePlusTime: boolean;

    // Used in conjunction with cellTemplate
    @Input() cellContext: any;
    @Input() cellTemplate: TemplateRef<any>;

    // get a reference to our container grid.
    constructor(@Host() private grid: GridComponent) {}

    ngOnInit() {

        if (!this.grid) {
            console.warn('GridColumnComponent needs an <eg-grid>');
            return;
        }

        const col = new GridColumn();
        col.name = this.name;
        col.path = this.path;
        col.label = this.label;
        col.flex = this.flex;
        col.hidden = this.hidden === true;
        col.isIndex = this.index === true;
        col.cellTemplate = this.cellTemplate;
        col.cellContext = this.cellContext;
        col.isSortable = this.sortable;
        col.isMultiSortable = this.multiSortable;
        col.datatype = this.datatype;
        col.datePlusTime = this.datePlusTime;
        col.isAuto = false;
        this.grid.context.columnSet.add(col);
    }
}

