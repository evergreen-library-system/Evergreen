import {Directive, Input} from '@angular/core';
import {NG_VALIDATORS, AbstractControl, FormControl, ValidationErrors, ValidatorFn} from '@angular/forms';
import {Injectable} from '@angular/core';

import * as moment from 'moment-timezone';

export function notBeforeMomentValidator(notBeforeMe: moment.Moment): ValidatorFn {
    return (control: AbstractControl): {[key: string]: any} | null => {
        return (control.value && control.value.isBefore(notBeforeMe)) ?
            {tooEarly: 'This cannot be before ' + notBeforeMe.format('LLL')} : null;
    };
}

@Directive({
    selector: '[egNotBeforeMoment]',
    providers: [{
        provide: NG_VALIDATORS,
        useExisting: NotBeforeMomentValidatorDirective,
        multi: true
    }]
})
export class NotBeforeMomentValidatorDirective {
    @Input('egNotBeforeMoment') notBeforeMoment: moment.Moment;

    validate(control: AbstractControl): {[key: string]: any} | null {
        return this.notBeforeMoment ?
            notBeforeMomentValidator(this.notBeforeMoment)(control)
            : null;
    }
}


