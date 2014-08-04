'use strict';

describe('egIDL', function(){
    beforeEach(module('egCoreMod'));

    it('should parse the IDL', inject(function(egIDL) {
        egIDL.parseIDL();
        expect(egIDL.classes.aou.fields.length).toBeGreaterThan(0);
    }));

    it('should create an aou object', inject(function(egIDL) {
        egIDL.parseIDL();
        var org = new egIDL.aou();
        expect(typeof org.id).toBe('function');
    }));

    it('should create an aou object with accessor/mutators', inject(function(egIDL) {
        egIDL.parseIDL();
        var org = new egIDL.aou();
        org.name('AN ORG');
        expect(org.name()).toBe('AN ORG');
    }));
});


