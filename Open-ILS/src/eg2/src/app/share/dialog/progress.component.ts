import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
  selector: 'eg-progress-dialog',
  templateUrl: './progress.component.html',
  styleUrls: ['progress.component.css']
})

/**
 * TODO: This duplicates the code from ProgressInlineComponent.
 * This component should insert to <eg-progress-inline/> into
 * its template instead of duplicating the code.  However, until
 * Angular bug https://github.com/angular/angular/issues/14842
 * is fixed, it's not possible to get a reference to the embedded
 * inline progress, which is needed for access the update/increment
 * API.
 * Also consider moving the progress traking logic to a service
 * to reduce code duplication.
 */

/**
 * Progress Dialog.
 *
 * // assuming a template reference...
 * @ViewChild('progressDialog')
 * private dialog: ProgressDialogComponent;
 *
 * dialog.open();
 * dialog.update({value : 0, max : 123});
 * dialog.increment();
 * dialog.increment();
 * dialog.close();
 *
 * Each dialog has 2 numbers, 'max' and 'value'.
 * The content of these values determines how the dialog displays.
 *
 * There are 3 flavors:
 *
 * -- value is set, max is set
 * determinate: shows a progression with a percent complete.
 *
 * -- value is set, max is unset
 * semi-determinate, with a value report.  Shows a value-less
 * <progress/>, but shows the value as a number in the dialog.
 *
 * This is useful in cases where the total number of items to retrieve
 * from the server is unknown, but we know how many items we've
 * retrieved thus far.  It helps to reinforce that something specific
 * is happening, but we don't know when it will end.
 *
 * -- value is unset
 * indeterminate: shows a generic value-less <progress/> with no
 * clear indication of progress.
 */
export class ProgressDialogComponent extends DialogComponent {

    max: number;
    value: number;

    reset() {
        delete this.max;
        delete this.value;
    }

    hasValue(): boolean {
        return Number.isInteger(this.value);
    }

    hasMax(): boolean {
        return Number.isInteger(this.max);
    }

    percent(): number {
        if (this.hasValue()  &&
            this.hasMax()    &&
            this.max > 0     &&
            this.value <= this.max) {
            return Math.floor((this.value / this.max) * 100);
        }
        return 100;
    }

    // Set the current state of the progress bar.
    update(args: {[key: string]: number}) {
        if (args.max !== undefined) {
            this.max = args.max;
        }
        if (args.value !== undefined) {
            this.value = args.value;
        }
    }

    // Increment the current value.  If no amount is specified,
    // it increments by 1.  Calling increment() on an indetermite
    // progress bar will force it to be a (semi-)determinate bar.
    increment(amt?: number) {
        if (!Number.isInteger(amt)) { amt = 1; }

        if (!this.hasValue()) {
            this.value = 0;
        }

        this.value += amt;
    }
}


