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

    it('should recreate an IDL object from a hash', () => {
        service.parseIdl();
        const hash = {
            id: 123,
            name: 'AN ORG',
            active: true
        };
        const org = service.fromHash(hash, 'aou');
        expect(org._isfieldmapper).toBe(true);
        expect(org.classname).toBe('aou');
        expect(org.id()).toBe(123);
        expect(org.name()).toBe('AN ORG');
        expect(org.active()).toBe(true);
    });

    it('should maintain data integrity through roundtrip conversion', () => {
        service.parseIdl();
        // Create an original IDL object with nested structure
        const original = service.create('aou');
        original.id(123);
        original.name('Test Org');
        original.active(true);

        const parent = service.create('aou');
        parent.id(456);
        parent.name('Parent Org');
        parent.active(false);
        original.parent(parent);

        // Convert to hash and back
        const hash = service.toHash(original);
        const roundtripped = service.fromHash(hash, 'aou', true);

        // Verify all properties maintained their values
        expect(roundtripped.id()).toBe(original.id());
        expect(roundtripped.name()).toBe(original.name());
        expect(roundtripped.active()).toBe(original.active());
        expect(roundtripped.parent().id()).toBe(original.parent().id());
        expect(roundtripped.parent().name()).toBe(original.parent().name());
        expect(roundtripped.parent().active()).toBe(original.parent().active());

        // Verify the objects have the same structure
        expect(roundtripped._isfieldmapper).toBe(true);
        expect(roundtripped.classname).toBe(original.classname);
        expect(roundtripped.parent()._isfieldmapper).toBe(true);
        expect(roundtripped.parent().classname).toBe(original.parent().classname);
    });

    it('should handle boolean conversion when enabled', () => {
        service.parseIdl();
        const hash = {
            id: 123,
            name: 'AN ORG',
            active: 't',  // PostgreSQL-style boolean
            'parent.active': 'f'
        };
        const org = service.fromHash(hash, 'aou', true);
        expect(org.active()).toBe(true);
        expect(org.parent().active()).toBe(false);
    });

    it('should handle nested IDL objects', () => {
        service.parseIdl();
        const hash = {
            id: 456,
            name: 'Child Org',
            parent: {
                id: 123,
                name: 'Parent Org'
            }
        };
        const org = service.fromHash(hash, 'aou');
        expect(org.parent()._isfieldmapper).toBe(true);
        expect(org.parent().classname).toBe('aou');
        expect(org.parent().id()).toBe(123);
        expect(org.parent().name()).toBe('Parent Org');
    });

    it('should handle flattened object notation', () => {
        service.parseIdl();
        const hash = {
            id: 456,
            name: 'Child Org',
            'parent.id': 123,
            'parent.name': 'Parent Org'
        };
        const org = service.fromHash(hash, 'aou');
        expect(org.parent()._isfieldmapper).toBe(true);
        expect(org.parent().classname).toBe('aou');
        expect(org.parent().id()).toBe(123);
        expect(org.parent().name()).toBe('Parent Org');
    });

    it('should handle arrays of IDL objects', () => {
        service.parseIdl();
        const hash = [{
            id: 1,
            name: 'First Org'
        }, {
            id: 2,
            name: 'Second Org'
        }];
        const orgs = service.fromHash(hash, 'aou');
        expect(Array.isArray(orgs)).toBe(true);
        expect(orgs[0]._isfieldmapper).toBe(true);
        expect(orgs[0].name()).toBe('First Org');
        expect(orgs[1].name()).toBe('Second Org');
    });

    it('should throw error for invalid base class', () => {
        service.parseIdl();
        const hash = { id: 123 };
        expect(() => service.fromHash(hash, 'not_a_class'))
            .toThrow('Invalid or missing base class: not_a_class');
    });

    it('should preserve primitive values', () => {
        service.parseIdl();
        expect(service.fromHash(123, 'aou')).toBe(123);
        expect(service.fromHash(null, 'aou')).toBe(null);
        expect(service.fromHash(undefined, 'aou')).toBe(undefined);
    });

});

