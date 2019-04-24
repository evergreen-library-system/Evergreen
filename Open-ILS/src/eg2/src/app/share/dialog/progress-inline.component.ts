import {Component, Input, ViewChild, TemplateRef} from '@angular/core';

/**
 * Inline Progress Bar
 *
 * // assuming a template reference...
 * @ViewChild('progress')
 * private progress: progressInlineComponent;
 *
 * progress.update({value : 0, max : 123});
 * progress.increment();
 * progress.increment();
 *
 * Each progress has 2 numbers, 'max' and 'value'.
 * The content of these values determines how the progress displays.
 *
 * There are 3 flavors:
 *
 * -- value is set, max is set
 * determinate: shows a progression with a percent complete.
 *
 * -- value is set, max is unset
 * semi-determinate, with a value report.  Shows a value-less
 * <progress/>, but shows the value as a number in the progress.
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
@Component({
  selector: 'eg-progress-inline',
  templateUrl: './progress-inline.component.html',
  styleUrls: ['progress-inline.component.css']
})
export class ProgressInlineComponent {

    @Input() max: number;
    @Input() value: number;

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


