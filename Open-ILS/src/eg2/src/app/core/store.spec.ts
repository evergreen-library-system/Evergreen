import {StoreService} from './store.service';
import {HatchService} from './hatch.service';
import { TestBed } from '@angular/core/testing';
import { CookieService } from 'ngx-cookie';

describe('StoreService', () => {
    let service: StoreService;
    beforeEach(() => {
        TestBed.configureTestingModule({providers: [
            {provide: CookieService, useValue: null},
            HatchService,
            StoreService
        ]});
        service = TestBed.inject(StoreService);
    });

    it('should set/get a localStorage value', () => {
        const str = 'hello, world';
        service.setLocalItem('testKey', str);
        expect(service.getLocalItem('testKey')).toBe(str);
    });

    it('should set/get a sessionStorage value', () => {
        const str = 'hello, world again';
        service.setLocalItem('testKey', str);
        expect(service.getLocalItem('testKey')).toBe(str);
    });

});

