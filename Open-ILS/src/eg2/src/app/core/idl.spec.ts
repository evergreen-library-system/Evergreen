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

    it('should sort an array of IDL fields according to an array of field names', () => {
        const fieldNames = ['name', 'owner', 'active', 'id'];
        const idlFields = [
            {'name': 'id', 'label': 'Object ID', 'dataType': 'id'},
            {'name': 'name', 'label': 'The name of this object', 'datatype': 'text'},
            {'name': 'active', 'datatype': 'bool'},
            {'name': 'owner', 'type': 'link', 'key': 'id', 'class': 'aou', 'reltype': 'has_a', 'datatype': 'org_unit'}
        ];
        const expectedOrder = [
            {'name': 'name', 'label': 'The name of this object', 'datatype': 'text'},
            {'name': 'owner', 'type': 'link', 'key': 'id', 'class': 'aou', 'reltype': 'has_a', 'datatype': 'org_unit'},
            {'name': 'active', 'datatype': 'bool'},
            {'name': 'id', 'label': 'Object ID', 'dataType': 'id'},
        ];
        expect(service.sortIdlFields(idlFields, fieldNames)).toEqual(expectedOrder);
    });

    it('should sort IDL fields by label when it runs out of specified field names', () => {
        const fieldNames = ['owner'];
        const idlFields = [
            {'name': 'id', 'label': 'Object ID', 'dataType': 'id'},
            {'name': 'name', 'label': 'The name of this object', 'datatype': 'text'},
            {'name': 'owner', 'type': 'link', 'key': 'id', 'class': 'aou', 'reltype': 'has_a', 'datatype': 'org_unit'}
        ];
        const expectedOrder = [
            {'name': 'owner', 'type': 'link', 'key': 'id', 'class': 'aou', 'reltype': 'has_a', 'datatype': 'org_unit'},
            {'name': 'id', 'label': 'Object ID', 'dataType': 'id'},
            {'name': 'name', 'label': 'The name of this object', 'datatype': 'text'},
        ];
        expect(service.sortIdlFields(idlFields, fieldNames)).toEqual(expectedOrder);
    });

    it('should sort IDL fields by name when it runs out of other ways to sort', () => {
        const fieldNames = ['owner'];
        const idlFields = [
            {'name': 'id', 'dataType': 'id'},
            {'name': 'name', 'label': 'The name of this object', 'datatype': 'text'},
            {'name': 'active', 'datatype': 'bool'},
            {'name': 'owner', 'type': 'link', 'key': 'id', 'class': 'aou', 'reltype': 'has_a', 'datatype': 'org_unit'}
        ];
        const expectedOrder = [
            {'name': 'owner', 'type': 'link', 'key': 'id', 'class': 'aou', 'reltype': 'has_a', 'datatype': 'org_unit'},
            {'name': 'name', 'label': 'The name of this object', 'datatype': 'text'},
            {'name': 'active', 'datatype': 'bool'},
            {'name': 'id', 'dataType': 'id'},
        ];
        expect(service.sortIdlFields(idlFields, fieldNames)).toEqual(expectedOrder);
    });

});

