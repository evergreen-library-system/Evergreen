/**
 * <eg-interval-input [(ngModel)]="interval">
 * </eg-interval-input>
 */
import {Component, OnInit, Input, Output, EventEmitter, forwardRef} from '@angular/core';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';

@Component({
    selector: 'eg-interval-input',
    templateUrl: './interval-input.component.html',
    providers: [{
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => IntervalInputComponent),
        multi: true
    }]
})
export class IntervalInputComponent implements ControlValueAccessor, OnInit {

    @Input() domId: string = 'eg-intv-' + Number(Math.random() * 1000);
    @Input() initialValue: string;
    @Input() disabled = false;
    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onChange = new EventEmitter<string>();

    period: string;
    unit = 'days';

    // Stub functions required by ControlValueAccessor
    propagateChange = (_: any) => {};
    propagateTouch = () => {};

    ngOnInit() {
        if (this.initialValue) {
            this.writeValue(this.initialValue);
        }
    }

    changeListener(): void {
        this.propagateChange(this.period + ' ' + this.unit);
        this.onChange.emit(this.period + ' ' + this.unit);
    }

    writeValue(value: string) {
        if (value) {
            this.period = value.split(' ')[0];
            this.unit   = value.split(' ')[1];
        }
    }

    registerOnChange(fn) {
        this.propagateChange = fn;
    }

    registerOnTouched(fn) {
        this.propagateTouch = fn;
    }
}
