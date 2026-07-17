import { Directive, forwardRef, Injectable, inject } from '@angular/core';
import {NG_ASYNC_VALIDATORS, AsyncValidator, FormControl} from '@angular/forms';
import {of, switchMap, catchError} from 'rxjs';
import {PcrudService} from '@eg/core/pcrud.service';

@Injectable({providedIn: 'root'})
export class BookingResourceBarcodeValidator implements AsyncValidator {
    private pcrud = inject(PcrudService);


    validate = (control: FormControl) => {
        return this.pcrud.search('brsrc',
            {'barcode' : control.value},
            {'limit': 1}).pipe(
            switchMap(() => of(null)),
            catchError((err: unknown) => {
                return of({ resourceBarcode: 'No resource found with that barcode' });
            }));
    };
}

@Directive({
    selector: '[egValidBookingResourceBarcode]',
    providers: [{
        provide: NG_ASYNC_VALIDATORS,
        useExisting: forwardRef(() => BookingResourceBarcodeValidator),
        multi: true
    }]
})

export class BookingResourceBarcodeValidatorDirective {
    private validator = inject(BookingResourceBarcodeValidator);


    validate = (control: FormControl) => {
        this.validator.validate(control);
    };
}

