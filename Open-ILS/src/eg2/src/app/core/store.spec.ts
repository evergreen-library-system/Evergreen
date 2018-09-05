import {StoreService} from './store.service';

describe('StoreService', () => {
    let service: StoreService;
    beforeEach(() => {
        service = new StoreService(null /* CookieService */);
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

