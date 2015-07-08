'use strict';

describe('egGridColumnsProvider', function(){
    beforeEach(module('egCoreMod'));
    beforeEach(module('egGridMod'));

    it('expand eg-grid-field wildcard paths', inject(function(egGridColumnsProvider, egIDL) {
        egIDL.parseIDL();
        var cols = egGridColumnsProvider.instance({
           idlClass : "circ" 
        });
        cols.expandPath({
            path : "*"
        });
        // the next two are regression tests for LP#1472787
        expect(cols.indexOf("grace_period")).not.toBe(-1);
        expect(cols.indexOf(".grace_period")).toBe(-1);
        cols.expandPath({
            path : "usr.*"
        });
        expect(cols.indexOf("usr.family_name")).not.toBe(-1);
    }));
});
