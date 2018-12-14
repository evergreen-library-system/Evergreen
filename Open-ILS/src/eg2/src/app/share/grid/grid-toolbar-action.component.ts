import {Component, Input, OnInit, Host, TemplateRef} from '@angular/core';
import {GridToolbarAction} from './grid';
import {GridComponent} from './grid.component';

@Component({
  selector: 'eg-grid-toolbar-action',
  template: '<ng-template></ng-template>'
})

export class GridToolbarActionComponent implements OnInit {

    // Note most input fields should match class fields for GridColumn
    @Input() label: string;
    @Input() action: (rows: any[]) => any;

    // Optional: add a function that returns true or false.
    // If true, this action will be disabled; if false
    // (default behavior), the action will be enabled.
    @Input() disabled: (rows: any[]) => boolean;

    // get a reference to our container grid.
    constructor(@Host() private grid: GridComponent) {}

    ngOnInit() {

        if (!this.grid) {
            console.warn('GridToolbarActionComponent needs a [grid]');
            return;
        }

        const action = new GridToolbarAction();
        action.label = this.label;
        action.action = this.action;

        action.disabled = (this.disabled == null) ? (rows: any[]) => false : this.disabled;


        this.grid.context.toolbarActions.push(action);
    }
}
