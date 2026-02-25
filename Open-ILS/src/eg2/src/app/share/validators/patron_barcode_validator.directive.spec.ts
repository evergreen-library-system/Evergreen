import {PatronBarcodeValidator} from './patron_barcode_validator.directive';
import {of} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import { MockGenerators } from 'test_data/mock_generators';
import { TestBed } from '@angular/core/testing';


describe('PatronBarcodeValidator', () => {
    beforeEach(() => {
        TestBed.configureTestingModule({providers: [
            {provide: AuthService, useValue: MockGenerators.authService()},
            {provide: NetService, useValue: MockGenerators.netService({})},
            PatronBarcodeValidator
        ]});
    });

    it('should not throw an error if there is exactly 1 match', () => {
        const pbv = TestBed.inject(PatronBarcodeValidator);
        pbv['parseActorCall'](of(1))
            .subscribe((val) => {
                expect(val).toBeNull();
            });
    });
    it('should throw an error if there is more than 1 match', () => {
        const pbv = TestBed.inject(PatronBarcodeValidator);
        pbv['parseActorCall'](of(1, 2, 3))
            .subscribe((val) => {
                expect(val).not.toBeNull();
            });
    });
    it('should throw an error if there is no match', () => {
        const pbv = TestBed.inject(PatronBarcodeValidator);
        pbv['parseActorCall'](of())
            .subscribe((val) => {
                expect(val).not.toBeNull();
            });
    });
});

