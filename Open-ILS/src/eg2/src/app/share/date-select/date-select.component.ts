/* eslint-disable eqeqeq */
import {Component, OnInit, Input, Output, EventEmitter, forwardRef} from '@angular/core';
import {NgbDateStruct} from '@ng-bootstrap/ng-bootstrap';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';
import {DateUtil} from '@eg/share/util/date';

/**
 * RE: displaying locale dates in the input field:
 * https://github.com/ng-bootstrap/ng-bootstrap/issues/754
 * https://stackoverflow.com/questions/40664523/angular2-ngbdatepicker-how-to-format-date-in-inputfield
 */

@Component({
    selector: 'eg-date-select',
    templateUrl: './date-select.component.html',
    styleUrls: ['date-select.component.css'],
    providers: [ {
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => DateSelectComponent),
        multi: true
    } ]
})
export class DateSelectComponent implements OnInit, ControlValueAccessor {

    @Input() initialIso: string; // ISO string
    @Input() initialYmd: string; // YYYY-MM-DD (uses local time zone)
    @Input() initialDate: Date;  // Date object
    @Input() required: boolean;
    @Input() fieldName: string;
    @Input() domId = '';
    @Input() disabled: boolean;
    @Input() readOnly: boolean;

    // Sometimes it's helpful to allow the date selector to expand
    // to fill its container for visual consistency with other inputs.
    @Input() noMaxWidth = false;

    current: NgbDateStruct;

    @Output() onChangeAsDate: EventEmitter<Date>;
    @Output() onChangeAsIso: EventEmitter<string>;
    @Output() onChangeAsYmd: EventEmitter<string>;
    @Output() onCleared: EventEmitter<string>;

    // convenience methods to access current selected date
    currentAsYmd(): string {
        if (this.current == null) { return null; }
        if (!this.isValidDate(this.current)) { return null; }
        return `${this.current.year}-${String(this.current.month).padStart(2, '0')}-${String(this.current.day).padStart(2, '0')}`;
    }
    currentAsIso(): string {
        if (this.current == null) { return null; }
        if (!this.isValidDate(this.current)) { return null; }
        const ymd = `${this.current.year}-${String(this.current.month).padStart(2, '0')}-${String(this.current.day).padStart(2, '0')}`;
        const date = DateUtil.localDateFromYmd(ymd);
        const iso = date.toISOString();
        return iso;
    }
    currentAsDate(): Date {
        if (this.current == null) { return null; }
        if (!this.isValidDate(this.current)) { return null; }
        const ymd = `${this.current.year}-${String(this.current.month).padStart(2, '0')}-${String(this.current.day).padStart(2, '0')}`;
        const date = DateUtil.localDateFromYmd(ymd);
        return date;
    }

    // Stub functions required by ControlValueAccessor
    propagateChange = (_: any) => {};
    propagateTouch = () => {};

    constructor() {
        this.onChangeAsDate = new EventEmitter<Date>();
        this.onChangeAsIso = new EventEmitter<string>();
        this.onChangeAsYmd = new EventEmitter<string>();
        this.onCleared = new EventEmitter<string>();
    }

    ngOnInit() {

        if (this.initialYmd) {
            this.initialDate = DateUtil.localDateFromYmd(this.initialYmd);

        } else if (this.initialIso) {
            this.initialDate = new Date(this.initialIso);
        }

        if (this.initialDate) {
            this.writeValue(this.initialDate);
        }
    }

    isValidDate(dt: NgbDateStruct): dt is NgbDateStruct {
        if (!dt) { return false; }
        return (<NgbDateStruct>dt).year !== undefined;
    }

    onDateEnter() {
        if (this.current === null) {
            this.onCleared.emit('cleared');
        } else if (this.isValidDate(this.current)) {
            this.onDateSelect(this.current);
        }
        // ignoring invalid input for now
    }

    onDateSelect(evt) {
        const ymd = `${evt.year}-${String(evt.month).padStart(2, '0')}-${String(evt.day).padStart(2, '0')}`;
        const date = DateUtil.localDateFromYmd(ymd);
        const iso = date.toISOString();
        this.onChangeAsDate.emit(date);
        this.onChangeAsYmd.emit(ymd);
        this.onChangeAsIso.emit(iso);
        this.propagateChange(date);
    }

    // onDateSelect() is not called when the value is cleared.
    // Handle that here.
    inputChanged(value) {
        if (value === null) {
            this.onChangeAsDate.emit(null);
            this.onChangeAsYmd.emit(null);
            this.onChangeAsIso.emit(null);
            this.propagateChange(null);
        }
    }

    reset() {
        this.current = {
            year: null,
            month: null,
            day: null
        };
    }

    writeValue(value: any) {
        if (typeof value === 'string') {
            value = new Date(value);
        }
        if (value && value instanceof Date && !isNaN(value.getTime())) {
            this.current = {
                year: value.getFullYear(),
                month: value.getMonth() + 1,
                day: value.getDate()
            };
        } else {
            // Allow the value to be cleared via model change.
            this.current = null;
        }
    }

    registerOnChange(fn) {
        this.propagateChange = fn;
    }

    registerOnTouched(fn) {
        this.propagateTouch = fn;
    }
}


