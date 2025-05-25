// eslint-disable @angular-eslint/no-output-on-prefix
import {Component, EventEmitter, Input, Output, ViewChild, OnInit, Optional, Self} from '@angular/core';
import {FormatService} from '@eg/core/format.service';
import {AbstractControl, ControlValueAccessor, FormControl, FormGroup, NgControl} from '@angular/forms';
import {DatetimeValidator} from '@eg/share/validators/datetime_validator.directive';
import * as moment from 'moment-timezone';
import {DateUtil} from '@eg/share/util/date';

@Component({
    selector: 'eg-datetime-select',
    templateUrl: './datetime-select.component.html',
})
export class DateTimeSelectComponent implements OnInit, ControlValueAccessor {
    @Input() domId = '';
    @Input() fieldName: string;
    @Input() initialIso: string;
    @Input() required: boolean;
    @Input() minuteStep = 15; // eslint-disable-line no-magic-numbers
    @Input() showTZ = true;
    @Input() timezone: string = this.format.wsOrgTimezone;
    @Input() readOnly = false;
    @Input() noPast = false;
    @Input() noFuture = false;
    @Input() minDate: any;
    @Input() maxDate: any;
    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onChangeAsIso: EventEmitter<string>;

    dateTimeForm: FormGroup;

    @ViewChild('datePicker', { static: false }) datePicker;

    onChange = (_: any) => {};
    onTouched = () => {};

    constructor(
        private format: FormatService,
        private dtv: DatetimeValidator,
        @Optional()
        @Self()
        public controlDir: NgControl, // so that the template can access validation state
    ) {
        if (controlDir) { controlDir.valueAccessor = this; }
        this.onChangeAsIso = new EventEmitter<string>();
        const startValue = moment.tz([], this.timezone);
        this.dateTimeForm = new FormGroup({
            'stringVersion': new FormControl(
                this.format.transform({value: startValue, datatype: 'timestamp', datePlusTime: true}),
                this.dtv.validate),
            'date': new FormControl({
                year: startValue.year(),
                month: startValue.month() + 1,
                day: startValue.date() }),
            'time': new FormControl({
                hour: startValue.hour(),
                minute: startValue.minute(),
                second: 0 })
        });
    }

    ngOnInit() {
        if (this.noPast) {
            this.minDate = DateUtil.localYmdPartsFromDate();
        }
        if (this.noFuture) {
            this.maxDate = DateUtil.localYmdPartsFromDate();
        }
        if (!this.timezone) {
            this.timezone = this.format.wsOrgTimezone;
        }
        if (this.initialIso) {
            this.writeValue(moment(this.initialIso).tz(this.timezone));
        }
        this.dateTimeForm.get('stringVersion').valueChanges.subscribe((value) => {
            if ('VALID' === this.dateTimeForm.get('stringVersion').status) {
                const model = this.format.momentizeDateTimeString(value, this.timezone, false);
                if (model && model.isValid()) {
                    this.onChange(model);
                    this.onChangeAsIso.emit(model.toISOString());
                    this.dateTimeForm.patchValue({date: {
                        year: model.year(),
                        month: model.month() + 1,
                        day: model.date()}, time: {
                        hour: model.hour(),
                        minute: model.minute(),
                        second: 0 }
                    }, {emitEvent: false, onlySelf: true});
                    this.datePicker.navigateTo({
                        year: model.year(),
                        month: model.month() + 1
                    });
                }
            }
        });
        this.dateTimeForm.get('date').valueChanges.subscribe((date) => {
            const newDate = moment.tz([date.year, (date.month - 1), date.day,
                this.time.value.hour, this.time.value.minute, 0], this.timezone);
            this.dateTimeForm.patchValue({stringVersion:
                this.format.transform({value: newDate, datatype: 'timestamp', datePlusTime: true})},
            {emitEvent: false, onlySelf: true});
            this.onChange(newDate);
            this.onChangeAsIso.emit(newDate.toISOString());
        });

        this.dateTimeForm.get('time').valueChanges.subscribe((time) => {
            const newDate = moment.tz([this.date.value.year,
                (this.date.value.month - 1),
                this.date.value.day,
                time.hour, time.minute, 0],
            this.timezone);
            this.dateTimeForm.patchValue({stringVersion:
                this.format.transform({
                    value: newDate, datatype: 'timestamp', datePlusTime: true})},
            {emitEvent: false, onlySelf: true});
            this.onChange(newDate);
            this.onChangeAsIso.emit(newDate.toISOString());
        });
    }

    setDatePicker(current: moment.Moment) {
        const withTZ = current ? current.tz(this.timezone) : moment.tz([], this.timezone);
        this.dateTimeForm.patchValue({date: {
            year: withTZ.year(),
            month: withTZ.month() + 1,
            day: withTZ.date() }});
    }

    setTimePicker(current: moment.Moment) {
        const withTZ = current ? current.tz(this.timezone) : moment.tz([], this.timezone);
        this.dateTimeForm.patchValue({time: {
            hour: withTZ.hour(),
            minute: withTZ.minute(),
            second: 0 }});
    }


    writeValue(value: moment.Moment|string) {
        if (typeof value === 'string') {
            if (value.length === 0) {
                return;
            }
            value = this.format.momentizeIsoString(value, this.timezone);
        }

        if (value !== undefined && value !== null) {
            this.dateTimeForm.patchValue({
                stringVersion: this.format.transform({value: value, datatype: 'timestamp', datePlusTime: true})});
            this.setDatePicker(value);
            this.setTimePicker(value);
        }
    }

    registerOnChange(fn: (value: moment.Moment) => any): void {
        this.onChange = fn;
    }
    registerOnTouched(fn: () => any): void {
        this.onTouched = fn;
    }

    firstError(errors: Object) {
        return Object.values(errors)[0];
    }

    get stringVersion(): AbstractControl {
        return this.dateTimeForm.get('stringVersion');
    }

    get date(): AbstractControl {
        return this.dateTimeForm.get('date');
    }

    get time(): AbstractControl {
        return this.dateTimeForm.get('time');
    }

}

