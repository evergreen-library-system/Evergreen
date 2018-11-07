import {Component, OnInit, Input, Output, ViewChild, EventEmitter} from '@angular/core';
import {NgbDateStruct} from '@ng-bootstrap/ng-bootstrap';

/**
 * RE: displaying locale dates in the input field:
 * https://github.com/ng-bootstrap/ng-bootstrap/issues/754
 * https://stackoverflow.com/questions/40664523/angular2-ngbdatepicker-how-to-format-date-in-inputfield
 */

@Component({
  selector: 'eg-date-select',
  templateUrl: './date-select.component.html'
})
export class DateSelectComponent implements OnInit {

    @Input() initialIso: string; // ISO string
    @Input() initialYmd: string; // YYYY-MM-DD (uses local time zone)
    @Input() initialDate: Date;  // Date object
    @Input() required: boolean;
    @Input() fieldName: string;
    @Input() domId = '';

    _disabled: boolean;
    @Input() set disabled(d: boolean) {
        this._disabled = d;
    }

    current: NgbDateStruct;

    @Output() onChangeAsDate: EventEmitter<Date>;
    @Output() onChangeAsIso: EventEmitter<string>;
    @Output() onChangeAsYmd: EventEmitter<string>;

    constructor() {
        this.onChangeAsDate = new EventEmitter<Date>();
        this.onChangeAsIso = new EventEmitter<string>();
        this.onChangeAsYmd = new EventEmitter<string>();
    }

    ngOnInit() {

        if (this.initialYmd) {
            this.initialDate = this.localDateFromYmd(this.initialYmd);

        } else if (this.initialIso) {
            this.initialDate = new Date(this.initialIso);
        }

        if (this.initialDate) {
            this.current = {
                year: this.initialDate.getFullYear(),
                month: this.initialDate.getMonth() + 1,
                day: this.initialDate.getDate()
            };
        }
    }

    onDateSelect(evt) {
        const ymd = `${evt.year}-${evt.month}-${evt.day}`;
        const date = this.localDateFromYmd(ymd);
        const iso = date.toISOString();
        this.onChangeAsDate.emit(date);
        this.onChangeAsYmd.emit(ymd);
        this.onChangeAsIso.emit(iso);
    }

    // Create a date in the local time zone with selected YMD values.
    // TODO: Consider moving this to a date service...
    localDateFromYmd(ymd: string): Date {
        const parts = ymd.split('-');
        return new Date(
            Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }
}


