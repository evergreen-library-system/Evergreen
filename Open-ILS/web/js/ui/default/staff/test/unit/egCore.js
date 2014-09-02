'use strict';

describe('egCore', function(){
    beforeEach(module('egCoreMod'));

    it('should wrap services', inject(function(egCore, egIDL) {
        expect(egCore.idl).toBe(egIDL);
    }));

    it('should wrap services', inject(function(egCore, egIDL) {
        expect(egCore.auth).not.toBe(egIDL);
    }));

    it('should not wrap non-services', inject(function(egCore) {
        expect(egCore.junk).not.toBeDefined();
    }));

});
