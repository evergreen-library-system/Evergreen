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

    it('should correctly compare IDL pkey values', () => {
        service.parseIdl();
        const org1 = service.create('aou');
        const org2 = service.create('aou');
        org1.id(123);
        org2.id(123);
        expect(service.pkeyMatches(org1, org2)).toBe(true);
    });

    it('should correctly compare IDL pkey values', () => {
        service.parseIdl();
        const org1 = service.create('aou');
        const org2 = service.create('aou');
        org1.id(123);
        org2.id(456);
        expect(service.pkeyMatches(org1, org2)).toBe(false);
    });

    it('should correctly compare IDL classes in pkey match', () => {
        service.parseIdl();
        const org = service.create('aou');
        const user = service.create('au');
        org.id(123);
        user.id(123);
        expect(service.pkeyMatches(org, user)).toBe(false);
    });


});

