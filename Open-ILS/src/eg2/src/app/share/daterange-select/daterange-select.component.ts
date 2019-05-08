import {Component, Input, forwardRef, OnInit} from '@angular/core';
import {NgbDate, NgbCalendar} from '@ng-bootstrap/ng-bootstrap';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';

export interface DateRange {
    fromDate?: NgbDate;
    toDate?: NgbDate;
}

@Component({
    selector: 'eg-daterange-select',
    templateUrl: './daterange-select.component.html',
    styleUrls: [ './daterange-select.component.css' ],
    providers: [{
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => DateRangeSelectComponent),
        multi: true
    }]
})
export class DateRangeSelectComponent implements ControlValueAccessor, OnInit {

    // Number of days in the initial
    // date range shown to user
    @Input() initialRangeLength = 10;

    // Start date of the initial
    // date range shown to user
    @Input() initialRangeStart = new Date();

    hoveredDate: NgbDate;

    selectedRange: DateRange;

    // Function to disable certain dates
    @Input() markDisabled:
        (date: NgbDate, current: { year: number; month: number; }) => boolean =
        (date: NgbDate, current: { year: number; month: number; }) => false

    onChange = (_: any) => {};
    onTouched = () => {};

    constructor(private calendar: NgbCalendar) { }

    ngOnInit() {
        this.selectedRange = {
            fromDate: new NgbDate(
                this.initialRangeStart.getFullYear(),
                this.initialRangeStart.getMonth() + 1,
                this.initialRangeStart.getDate()),
            toDate: this.calendar.getNext(
                this.calendar.getToday(),
                'd',
                this.initialRangeLength)
        };
    }

    onDateSelection(date: NgbDate) {
        if (!this.selectedRange.fromDate && !this.selectedRange.toDate) {
            this.selectedRange.fromDate = date;
        } else if (this.selectedRange.fromDate && !this.selectedRange.toDate && date.after(this.selectedRange.fromDate)) {
            this.selectedRange.toDate = date;
        } else {
            this.selectedRange.toDate = null;
            this.selectedRange.fromDate = date;
        }
        this.onChange(this.selectedRange);
    }

    isHovered(date: NgbDate) {
        return this.selectedRange.fromDate &&
            !this.selectedRange.toDate &&
            this.hoveredDate &&
            date.after(this.selectedRange.fromDate) &&
            date.before(this.hoveredDate);
    }

    isInside(date: NgbDate) {
        return date.after(this.selectedRange.fromDate) && date.before(this.selectedRange.toDate);
    }

    isRange(date: NgbDate) {
        return date.equals(this.selectedRange.fromDate) ||
            date.equals(this.selectedRange.toDate) ||
            this.isInside(date) ||
            this.isHovered(date);
    }

    writeValue(value: DateRange) {
        if (value) {
            this.selectedRange = value;
        }
    }
    registerOnChange(fn: (value: DateRange) => any): void {
        this.onChange = fn;
    }
    registerOnTouched(fn: () => any): void {
        this.onTouched = fn;
    }
    today(): NgbDate {
        return this.calendar.getToday();
    }
}
