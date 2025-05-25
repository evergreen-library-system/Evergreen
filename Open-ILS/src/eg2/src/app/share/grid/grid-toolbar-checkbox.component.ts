import {Component, Input, OnInit, Host, Output, EventEmitter} from '@angular/core';
import {GridToolbarCheckbox} from './grid';
import {GridComponent} from './grid.component';

@Component({
    selector: 'eg-grid-toolbar-checkbox',
    template: '<ng-template></ng-template>'
})

export class GridToolbarCheckboxComponent implements OnInit {

    // Note most input fields should match class fields for GridColumn
    @Input() label: string;

    // Set the render time value.
    // This does NOT fire the onChange handler.
    @Input() initialValue: boolean;

    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onChange: EventEmitter<boolean>;

    private cb: GridToolbarCheckbox;

    // get a reference to our container grid.
    constructor(@Host() private grid: GridComponent) {
        this.onChange = new EventEmitter<boolean>();

        // Create in constructor so we can accept values before the
        // grid is fully rendered.
        this.cb = new GridToolbarCheckbox();
        this.cb.isChecked = null;
        this.initialValue = null;
    }

    ngOnInit() {
        if (!this.grid) {
            console.warn('GridToolbarCheckboxComponent needs a [grid]');
            return;
        }

        this.cb.label = this.label;
        this.cb.onChange = this.onChange;

        if (this.cb.isChecked === null && this.initialValue !== null) {
            this.cb.isChecked = this.initialValue;
        }

        this.grid.context.toolbarCheckboxes.push(this.cb);
    }

    // Toggle the value.  onChange is not fired.
    toggle() {
        this.cb.isChecked = !this.cb.isChecked;
    }

    // Set/get the value.  onChange is not fired.
    checked(value?: boolean): boolean {
        if (value === true || value === false) {
            this.cb.isChecked = value;
        }
        return this.cb.isChecked;
    }
}

