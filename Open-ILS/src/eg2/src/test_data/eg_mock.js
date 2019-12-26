/**
 * Mock data required by multiple unit tests.
 */

window._eg_mock_data = {

    // builds a mock org unit tree fleshed with ou_types and
    // absorbs the tree into egEnv
    generateOrgTree : function(idlService, orgService) {
        var type1 = idlService.create('aout');
        type1.id(1);
        type1.depth(0);

        var type2 = idlService.create('aout');
        type2.id(2);
        type2.depth(1);
        type2.parent(1);

        var type3 = idlService.create('aout');
        type3.id(3);
        type3.depth(2);
        type3.parent(2);

        var org1 = idlService.create('aou'); 
        org1.id(1);
        org1.ou_type(type1);
        org1.shortname('ROOT');

        var org2 = idlService.create('aou'); 
        org2.id(2); 
        org2.parent_ou(1);
        org2.ou_type(type2);
        org2.shortname('B'); // to test sorting

        var org3 = idlService.create('aou'); 
        org3.id(3); 
        org3.parent_ou(1);
        org3.ou_type(type2);
        org3.shortname('A'); // to test sorting

        var org4 = idlService.create('aou'); 
        org4.id(4); 
        org4.parent_ou(2);
        org4.ou_type(type3);

        org1.children([org2, org3]);
        org2.children([org4]);
        org3.children([]);
        org4.children([]);

        orgService.orgTree = org1;
        orgService.absorbTree();
    }
}
