import {Component, Input, OnInit, Host, TemplateRef} from '@angular/core';
import {GridColumn} from './grid';
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

    // If true, boolean fields support 3 values: true, false, null (unset)
    @Input() ternaryBool: boolean;

    // result filtering
    @Input() filterable: boolean;

    // Display date and time when datatype = timestamp
    @Input() datePlusTime: boolean;

    // Display using a specific OU's timestamp when datatype = timestamp
    @Input() timezoneContextOrg: number;

    // Used in conjunction with cellTemplate
    @Input() cellContext: any;
    @Input() cellTemplate: TemplateRef<any>;

    @Input() disableTooltip: boolean;

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
        col.disableTooltip = this.disableTooltip;
        col.isSortable = this.sortable;
        col.isFilterable = this.filterable;
        col.isMultiSortable = this.multiSortable;
        col.datatype = this.datatype;
        col.datePlusTime = this.datePlusTime;
        col.ternaryBool = this.ternaryBool;
        col.timezoneContextOrg = this.timezoneContextOrg;
        col.isAuto = false;
        this.grid.context.columnSet.add(col);

        if (this.cellTemplate &&
            !this.grid.context.columnHasTextGenerator(col)) {
            console.warn(
                'No cellTextGenerator provided for "' + col.name + '"');
        }
    }
}

