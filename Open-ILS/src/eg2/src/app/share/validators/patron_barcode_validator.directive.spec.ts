import {PatronBarcodeValidator} from './patron_barcode_validator.directive';
import {of} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {StoreService} from '@eg/core/store.service';
import {HatchService} from '@eg/core/hatch.service';

let netService: NetService;
let authService: AuthService;
let evtService: EventService;
let storeService: StoreService;
let hatchService: HatchService;

beforeEach(() => {
    evtService = new EventService();
    hatchService = new HatchService();
    storeService = new StoreService(null /* CookieService */, hatchService);
    netService = new NetService(evtService);
    authService = new AuthService(evtService, netService, storeService);
});

describe('PatronBarcodeValidator', () => {
    it('should not throw an error if there is exactly 1 match', () => {
        const pbv = new PatronBarcodeValidator(authService, netService);
        pbv['parseActorCall'](of(1))
        .subscribe((val) => {
            expect(val).toBeNull();
        });
    });
    it('should throw an error if there is more than 1 match', () => {
        const pbv = new PatronBarcodeValidator(authService, netService);
        pbv['parseActorCall'](of(1, 2, 3))
        .subscribe((val) => {
            expect(val).not.toBeNull();
        });
    });
    it('should throw an error if there is no match', () => {
        const pbv = new PatronBarcodeValidator(authService, netService);
        pbv['parseActorCall'](of())
        .subscribe((val) => {
            expect(val).not.toBeNull();
        });
    });
});

