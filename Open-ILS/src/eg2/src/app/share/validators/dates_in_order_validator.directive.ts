/* eslint-disable no-unused-expressions */
import { Directive, Input } from '@angular/core';
import { AbstractControl, NG_VALIDATORS, ValidationErrors, Validator, ValidatorFn } from '@angular/forms';
import * as moment from 'moment';

export function datesInOrderValidator(fieldNames: string[]): ValidatorFn {
    return (control: AbstractControl): {[key: string]: any} | null => {
        if (fieldsAreInOrder(fieldNames, control)) {return null;}
        return {datesOutOfOrder: 'Dates should be in order'};
    };
}

function fieldsAreInOrder(fieldNames: string[], control: AbstractControl): boolean {
    if (fieldNames.length === 0) {return true;}
    return fieldNames.every((field, index) => {
        // No need to compare field[0] to the field before it
        if (index === 0) {return true;}

        const previousValue = moment(control.get(fieldNames[index - 1])?.value);
        const currentValue = moment(control.get(field)?.value);

        // If either field is invalid, return true -- there should be other
        // validation that can catch that
        if (!previousValue.isValid() || !currentValue.isValid()) {return true;}

        // Check each field against its predecessor
        return previousValue.isSameOrBefore(currentValue);
    });
}

@Directive({
    selector: '[egDateFieldOrderList]',
    providers: [{ provide: NG_VALIDATORS, useExisting: DatesInOrderValidatorDirective, multi: true }]
})
export class DatesInOrderValidatorDirective implements Validator {
    @Input('egDateFieldOrderList') dateFieldOrderList = '';
    validate(control: AbstractControl): ValidationErrors | null {
        if (this.dateFieldOrderList?.length > 0) {
            return datesInOrderValidator(this.dateFieldOrderList.split(','))(control);
        } else {
        // Don't run validations if we have no fields to examine
            return () => {null;};
        }
    }
}
