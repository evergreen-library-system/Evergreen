import {StoreService} from './store.service';
import {HatchService} from './hatch.service';

describe('StoreService', () => {
    let service: StoreService;
    let hatchService: HatchService;
    beforeEach(() => {
        hatchService = new HatchService();
        service = new StoreService(null /* CookieService */, hatchService);
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

