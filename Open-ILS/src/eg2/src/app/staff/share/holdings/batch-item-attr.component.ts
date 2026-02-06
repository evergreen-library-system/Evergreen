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
    styleUrls: ['batch-item-attr.component.css', '../../cat/volcopy/copy-attrs.component.css']
})

export class BatchItemAttrComponent implements OnInit {

    // Main display label, e.g. "Circulation Modifier"
    @Input() label: string;

    // Optional.  Useful for exracting information (i.e. hasChanges)
    // on a specific field from a set of batch attr components.
    @Input() name: string;

    // Maps display labels to the number of items that have the label.
    // e.g. {"Stacks": 4, "Display": 12}
    @Input() labelCounts: {[label: string]: number} = {};
    @Input() filteredLabelCounts: {[label: string]: number} = {};

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

    // Maybe display only, but items are selectable
    @Input() selectOnly = false;

    // when used in a template admin context; expect to use for styling
    @Input() templateOnlyMode = false;

    // Warn the user when a required field has an empty value
    @Input() valueRequired = false;
    requiredNotMet = false;
    aValueIsUnset = false;

    // If true, a value of '' is considered unset for display and
    // valueRequired purposes.
    @Input() emptyStringIsUnset = true;

    // Lists larger than this will be partially hidden behind
    // and expandy.
    @Input() defaultDisplayCount = 7;

    @Output() filterApplied: EventEmitter<BatchChangeSelection> =
        new EventEmitter<BatchChangeSelection>();

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

    ngOnInit() {
        this.checkValuesForCSS();
    }

    save($event?: Event) {
        if ($event) {
            $event.preventDefault();
            $event.stopPropagation();
        }
        this.hasChanged = true;
        this.editing = false;
        this.checkValuesForCSS();
        this.changesSaved.emit(this.editValues);
        this.focusLabel();
    }

    applyFilter($event?: Event) {
        if ($event) {
            $event.preventDefault();
            $event.stopPropagation();
        }
        this.editing = false;
        this.checkValuesForCSS();
        this.filterApplied.emit(this.editValues);
        this.focusLabel();
    }

    cancel($event?: Event) {
        if ($event) {
            $event.preventDefault();
            $event.stopPropagation();
        }
        this.editing = false;
        this.checkValuesForCSS();
        this.changesCanceled.emit();
        this.focusLabel();
    }

    selectAllForFilter($event?: Event) {
        if ($event) {
            $event.preventDefault();
            $event.stopPropagation();
        }
        Object.keys(this.labelCounts).forEach(key => this.editValues[key] = true);
    }
    selectNoneForFilter($event?: Event) {
        if ($event) {
            $event.preventDefault();
            $event.stopPropagation();
        }
        Object.keys(this.labelCounts).forEach(key => this.editValues[key] = false);
    }


    clear($event?: Event) {
        if ($event) {
            $event.preventDefault();
            $event.stopPropagation();
        }
        this.hasChanged = true;
        this.editing = false;
        this.checkValuesForCSS();
        this.valueCleared.emit();
        this.focusLabel();
    }

    focusLabel() {
        setTimeout(() => {
            // fieldset input[type="radio"]:checked for yes/no; label.edit-toggle for all others
            // eslint-disable-next-line max-len
            const input = document.querySelector(`.card:has(#label-${this.editInputDomId}) .edit-toggle, .card:has(#label-${this.editInputDomId}) fieldset input[type="radio"]:checked`) as HTMLElement;
            input?.focus();
        });
    }

    bulky(): boolean {
        if (this.selectOnly && !this.editing) {
            return Object.keys(this.filteredLabelCounts).length > this.defaultDisplayCount;
        }
        return Object.keys(this.labelCounts).length > this.defaultDisplayCount;
    }

    multiValue(): boolean {
        return Object.keys(this.labelCounts).length > 1;
    }

    checkValuesForCSS() {
        this.aValueIsUnset = this.testAllValuesForUnset();
        this.requiredNotMet = !!(this.valueRequired && this.aValueIsUnset && !this.templateOnlyMode);
        /* console.debug('checkValuesForCSS for ' + this.label, {
            'has-changes': !!this.hasChanged,
            'required': !!(this.valueRequired && !this.templateOnlyMode),
            'required-not-met': !!(this.valueRequired && this.requiredNotMet && !this.templateOnlyMode),
            'requiredNotMet': !!this.requiredNotMet,
            'required-met': !!(this.valueRequired && !this.requiredNotMet && !this.templateOnlyMode),
            'unset': !!this.aValueIsUnset,
            'templateOnlyMode': !!this.templateOnlyMode
        });*/
    }

    warnOnRequired(): boolean {
        this.checkValuesForCSS();
        return this.requiredNotMet;
    }

    testAllValuesForUnset(): boolean {
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

    enterFilterMode() {
        if (!this.selectOnly && (this.readOnly || this.editing)) { return; }
        this.editing = true;

        // Assume untouched values should be selected by default
        Object.keys(this.labelCounts).forEach(
            key => this.editValues[key] = this.editValues[key] === false ? false : true );

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



