/* eslint-disable no-magic-numbers */
import {Component, OnInit, Input, Output, TemplateRef,
    EventEmitter} from '@angular/core';

/**
 * Displays attribute values and associated copy counts for managing
 * updates to batches of items.
 */


// Map of display value to boolean indicating whether a given item
// should be modified.
export interface BatchChangeSelection {
    [value: string]: boolean;
}

@Component({
    selector: 'eg-batch-item-attr',
    templateUrl: 'batch-item-attr.component.html',
    styles: [
        '.header { background-color: #d9edf7; }',
        '.has-changes { background-color: #dff0d8; }'
    ]
})

export class BatchItemAttrComponent {

    // Main display label, e.g. "Circulation Modifier"
    @Input() label: string;

    // Optional.  Useful for exracting information (i.e. hasChanges)
    // on a specific field from a set of batch attr components.
    @Input() name: string;

    // Maps display labels to the number of items that have the label.
    // e.g. {"Stacks": 4, "Display": 12}
    @Input() labelCounts: {[label: string]: number} = {};

    // Ref to some type of edit widget for modifying the value.
    // Note this component simply displays the template, it does not
    // interact with the template in any way.
    @Input() editTemplate: TemplateRef<any>;

    @Input() editInputDomId = '';

    // In some cases, we can map display labels to something more
    // human friendly.
    @Input() displayAs: 'bool' | 'currency' = null;

    // Display only
    @Input() readOnly = false;

    // Warn the user when a required field has an empty value
    @Input() valueRequired = false;

    // If true, a value of '' is considered unset for display and
    // valueRequired purposes.
    @Input() emptyStringIsUnset = true;

    // Lists larger than this will be partially hidden behind
    // and expandy.
    @Input() defaultDisplayCount = 7;

    @Output() changesSaved: EventEmitter<BatchChangeSelection> =
        new EventEmitter<BatchChangeSelection>();

    @Output() changesCanceled: EventEmitter<void> = new EventEmitter<void>();
    @Output() valueCleared: EventEmitter<void> = new EventEmitter<void>();

    // Is the editTtemplate visible?
    editing = false;

    hasChanged = false;

    // Showing all entries?
    expanded = false;

    // Indicate which display values the user wants to modify.
    editValues: BatchChangeSelection = {};

    constructor() {}

    save() {
        this.hasChanged = true;
        this.editing = false;
        this.changesSaved.emit(this.editValues);
    }

    cancel() {
        this.editing = false;
        this.changesCanceled.emit();
    }

    clear() {
        this.hasChanged = true;
        this.editing = false;
        this.valueCleared.emit();
    }

    bulky(): boolean {
        return Object.keys(this.labelCounts).length > this.defaultDisplayCount;
    }

    multiValue(): boolean {
        return Object.keys(this.labelCounts).length > 1;
    }

    // True if a value is required and any value exists that's unset.
    warnOnRequired(): boolean {
        if (!this.valueRequired) { return false; }

        return Object.keys(this.labelCounts)
            .filter(key => this.valueIsUnset(key)).length > 0;
    }

    valueIsUnset(value: any): boolean {
        return (
            value === null ||
            value === undefined ||
            (this.emptyStringIsUnset && value === '')
        );
    }

    enterEditMode() {
        if (this.readOnly || this.editing) { return; }
        this.editing = true;

        // Assume all values should be edited by default
        Object.keys(this.labelCounts).forEach(
            key => this.editValues[key] = true);

        if (this.editInputDomId) {
            setTimeout(() => {
                // Avoid using selectRootElement to focus.
                // https://stackoverflow.com/a/36059595
                const node = document.getElementById(this.editInputDomId);
                if (node) { node.focus(); }
            });
        }
    }
}



