import { Directive, HostBinding, Input } from '@angular/core';
import { AbstractControl, NG_VALIDATORS, ValidationErrors, Validator, Validators } from '@angular/forms';

// https://stackoverflow.com/a/57812865
@Directive({
    selector: 'input[type=number][egMin][formControlName],input[type=number][egMin][formControl],input[type=number][egMin][ngModel]',
    providers: [{ provide: NG_VALIDATORS, useExisting: MinValidatorDirective, multi: true }]
})
export class MinValidatorDirective implements Validator {
    @HostBinding('attr.egMin') @Input() egMin: number;

    constructor() { }

    validate(control: AbstractControl): ValidationErrors | null {
        const validator = Validators.min(this.egMin);
        return validator(control);
    }
}
@Directive({
    selector: 'input[type=number][egMax][formControlName],input[type=number][egMax][formControl],input[type=number][egMax][ngModel]',
    providers: [{ provide: NG_VALIDATORS, useExisting: MaxValidatorDirective, multi: true }]
})
export class MaxValidatorDirective implements Validator {
    @HostBinding('attr.egMax') @Input() egMax: number;

    constructor() { }

    validate(control: AbstractControl): ValidationErrors | null {
        const validator = Validators.max(this.egMax);
        return validator(control);
    }
}
