import {Component, Input, OnInit, Host, TemplateRef} from '@angular/core';
import {GridToolbarCheckbox} from './grid';
import {GridComponent} from './grid.component';

@Component({
  selector: 'eg-grid-toolbar-checkbox',
  template: '<ng-template></ng-template>'
})

export class GridToolbarCheckboxComponent implements OnInit {

    // Note most input fields should match class fields for GridColumn
    @Input() label: string;

    // This is an input instead of an Output because the handler is
    // passed off to the grid context for maintenance -- events
    // are not fired directly from this component.
    @Input() onChange: (checked: boolean) => void;

    // get a reference to our container grid.
    constructor(@Host() private grid: GridComponent) {}

    ngOnInit() {

        if (!this.grid) {
            console.warn('GridToolbarCheckboxComponent needs a [grid]');
            return;
        }

        const cb = new GridToolbarCheckbox();
        cb.label = this.label;
        cb.onChange = this.onChange;

        this.grid.context.toolbarCheckboxes.push(cb);
    }
}

