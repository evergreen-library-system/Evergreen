import {IdlService} from './idl.service';

describe('IdlService', () => {
    let service: IdlService;
    beforeEach(() => {
        service = new IdlService();
    });

    it('should parse the IDL', () => {
        service.parseIdl();
        expect(service.classes['aou'].fields.length).toBeGreaterThan(0);
    });

    it('should create an aou object', () => {
        service.parseIdl();
        const org = service.create('aou');
        expect(typeof org.id).toBe('function');
    });

    it('should create an aou object with accessor/mutators', () => {
        service.parseIdl();
        const org = service.create('aou');
        org.name('AN ORG');
        expect(org.name()).toBe('AN ORG');
    });

});

