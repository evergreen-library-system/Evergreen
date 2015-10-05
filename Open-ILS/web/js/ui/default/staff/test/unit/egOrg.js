'use strict';

describe('egOrg', function(){
    beforeEach(module('egCoreMod'));

    function mkTree(egIDL, egEnv) { // FIXME: external sample data
        egIDL.parseIDL();
        window._eg_mock_data.orgTree(egIDL, egEnv);
    }

    it('should provide get by ID', inject(function(egIDL, egEnv, egOrg) {
        mkTree(egIDL, egEnv);
        expect(egOrg.get(egEnv.aou.tree.id())).toBe(egEnv.aou.tree);
    }));

    it('should provide get by node', inject(function(egIDL, egEnv, egOrg) {
        mkTree(egIDL, egEnv);
        expect(egOrg.get(egEnv.aou.tree).id()).toBe(egEnv.aou.tree.id());
    }));

    it('should provide ancestors', inject(function(egIDL, egEnv, egOrg) {
        mkTree(egIDL, egEnv);
        expect(egOrg.ancestors(2, true)).toEqual([2, 1]);
    }));

    it('should provide descendants', inject(function(egIDL, egEnv, egOrg) {
        mkTree(egIDL, egEnv);
        expect(egOrg.descendants(2, true)).toEqual([2, 4]);
    }));

    it('should provide full path', inject(function(egIDL, egEnv, egOrg) {
        mkTree(egIDL, egEnv);
        expect(egOrg.fullPath(4, true)).toEqual([4, 2, 1]);
    }));

    it('should provide root', inject(function(egIDL, egEnv, egOrg) {
        mkTree(egIDL, egEnv);
        expect(egOrg.root().id()).toEqual(1);
    }));
});


