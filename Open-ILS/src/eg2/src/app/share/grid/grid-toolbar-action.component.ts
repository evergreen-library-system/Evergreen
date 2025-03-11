import {Component, Input, Output, OnInit, Host, TemplateRef, EventEmitter} from '@angular/core';
import {GridToolbarAction} from './grid';
import {GridComponent} from './grid.component';

@Component({
    selector: 'eg-grid-toolbar-action',
    template: '<ng-template></ng-template>'
})

export class GridToolbarActionComponent implements OnInit {

    toolbarAction: GridToolbarAction;

    // Note most input fields should match class fields for GridColumn
    @Input() label: string;

    // Use `${gridDomId}-selection-count` as the button aria-describedby attribute?
    @Input() describedbySelectionCount = false;

    // Register to click events
    @Output() onClick: EventEmitter<any []>;

    // When present, actions will be grouped by the provided label.
    @Input() group: string;

    // DEPRECATED: Pass a reference to a function that is called on click.
    @Input() action: (rows: any[]) => any;

    @Input() set disabled(d: boolean) {
        if (this.toolbarAction) {
            this.toolbarAction.disabled = d;
        }
    }
    get disabled(): boolean {
        return this.toolbarAction.disabled;
    }

    // Optional: add a function that returns true or false.
    // If true, this action will be disabled; if false
    // (default behavior), the action will be enabled.
    @Input() disableOnRows: (rows: any[]) => boolean;

    // If true, render a separator bar only, no action link.
    @Input() isSeparator: boolean;

    // get a reference to our container grid.
    constructor(@Host() private grid: GridComponent) {
        this.onClick = new EventEmitter<any []>();
        this.toolbarAction = new GridToolbarAction();
    }

    ngOnInit() {

        if (!this.grid) {
            console.warn('GridToolbarActionComponent needs a [grid]');
            return;
        }

        if (this.action) {
            console.debug('toolbar [action] is deprecated. use (onClick) instead.');
        }

        this.toolbarAction.label = this.label;
        this.toolbarAction.onClick = this.onClick;
        this.toolbarAction.group = this.group;
        this.toolbarAction.action = this.action;
        this.toolbarAction.disabled = this.disabled;
        this.toolbarAction.isSeparator = this.isSeparator;
        this.toolbarAction.disableOnRows = this.disableOnRows;
        this.toolbarAction.describedbySelectionCount = this.describedbySelectionCount;
        this.grid.context.toolbarActions.push(this.toolbarAction);
    }
}
