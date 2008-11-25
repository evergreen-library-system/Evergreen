if(!dojo._hasResource["openils.PermGrp"]){
    dojo.provide("openils.PermGrp");
    dojo.require('openils.Util');

    dojo.declare( "openils.PermGrp", null, {});

    openils.PermGrp.groupTree = null;
    openils.PermGrp.groupIdMap = {};

    openils.PermGrp.fetchGroupTree = function(onload) {
        if(openils.PermGrp.groupTree) 
            return onload();
        fieldmapper.standardRequest(
            ['open-ils.actor', 'open-ils.actor.groups.tree.retrieve'],
            {   async: true,
                oncomplete: function(r) {
                    openils.PermGrp.groupTree = openils.Util.readResponse(r);
                    onload();
                }
            }
        );
    };

    /**
     * Flatten the group tree into a id => object map for easy access
     */
    openils.PermGrp.flatten = function(node) {
        if(!node) node = 
            openils.PermGrp.groupTree;
        openils.PermGrp.groupIdMap[node.id()] = node;
        for(var idx in node.children())
            openils.PermGrp.flatten(node.children()[idx]);
    };
}
