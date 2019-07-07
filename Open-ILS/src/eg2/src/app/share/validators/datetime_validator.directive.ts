import {Directive, forwardRef} from '@angular/core';
import {NG_VALIDATORS, AbstractControl, FormControl, ValidationErrors, Validator} from '@angular/forms';
import {FormatService} from '@eg/core/format.service';
import {EmptyError, Observable, of} from 'rxjs';
import {single, switchMap, catchError} from 'rxjs/operators';
import {Injectable} from '@angular/core';

@Injectable({providedIn: 'root'})
export class DatetimeValidator implements Validator {
    constructor(
        private format: FormatService) {
    }

    validate = (control: FormControl) => {
        try {
            this.format.momentizeDateTimeString(control.value, 'Africa/Addis_Ababa', true);
        } catch (err) {
            return {datetimeParseError: err.message};
        }
        return null;
    }
}

@Directive({
    selector: '[egValidDatetime]',
    providers: [{
        provide: NG_VALIDATORS,
        useExisting: DatetimeValidatorDirective,
        multi: true
    }]
})
export class DatetimeValidatorDirective {
    constructor(
        private dtv: DatetimeValidator
    ) { }

    validate = (control: FormControl) => {
        this.dtv.validate(control);
    }
}

