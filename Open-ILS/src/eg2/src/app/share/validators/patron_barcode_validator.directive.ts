import { Directive, forwardRef, Injectable } from '@angular/core';
import { NG_ASYNC_VALIDATORS, AsyncValidator, FormControl } from '@angular/forms';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EmptyError, Observable, SequenceError, of, single, switchMap, catchError} from 'rxjs';

@Injectable({providedIn: 'root'})
export class PatronBarcodeValidator implements AsyncValidator {
    constructor(
        private auth: AuthService,
        private net: NetService) {
    }

    validate = (control: FormControl) => {
        return this.parseActorCall(this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(),
            this.auth.user().ws_ou(),
            'actor', control.value.trim()));
    };

    private parseActorCall = (actorCall: Observable<any>) => {
        return actorCall
            .pipe(single(),
                switchMap(() => of(null)),
                catchError((err: unknown) => {
                    if (err instanceof EmptyError) {
                        return of({ patronBarcode: 'No patron found with that barcode' });
                    } else if (err instanceof SequenceError) {
                        return of({ patronBarcode: 'Barcode matches more than one patron' });
                    }
                }));
    };
}

@Directive({
    selector: '[egValidPatronBarcode]',
    providers: [{
        provide: NG_ASYNC_VALIDATORS,
        useExisting: forwardRef(() => PatronBarcodeValidator),
        multi: true
    }]
})
export class PatronBarcodeValidatorDirective {
    constructor(
        private pbv: PatronBarcodeValidator
    ) { }

    validate = (control: FormControl) => {
        this.pbv.validate(control);
    };
}

