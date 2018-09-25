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

        this.grid.context.toolbarActions.push(action);
    }
}

