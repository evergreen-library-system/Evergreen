/* */

function findOrgDepth(type_id) {

	if(type_id == null || globalOrgTypes == null)
		return null;

	var t = findOrgType(type_id);
	if(t != null)
		return t.depth();

	return null;
}

function findOrgType(type_id) {

	if(type_id == null || globalOrgTypes == null)
		return null;

	if(typeof type_id == 'object')
		return type_id;

	for(var type in globalOrgTypes) {
		var t =globalOrgTypes[type]; 
		if( t.id() == type_id || t.id() == parseInt(type_id) ) 
			return t;
	}
	return null;
}


/* locates a specific org unit */
function findOrgUnit(org_id, branch) {
	if(org_id == null) return null;
	if(typeof org_id == 'object') return org_id;
	if(globalOrgTree == null)
		throw new EXArg("Need globalOrgTree");

	if( branch == null )
		branch = globalOrgTree;

	if( org_id == branch.id() )
		return branch;

	var org;
	for( var child in branch.children() ) {
		org = findOrgUnit(org_id, branch.children()[child]);
		if(org != null) 
			return org;
	}
	return null;
}



function getOrgById(id, node) {
	if(node == null) node = globalOrgTree;
	if( node.id() == id) return node;
	for( var ind in node.children() ) {
		var ret = getOrgById(id, node.children()[ind] );
		if( ret != null )
			return ret;
	}
	return null;
}



function orgNodeTrail(node) {
	var nodeArray = new Array();
	while( node ) {
		nodeArray.push(node);
		node = findOrgUnit(node.parent_ou());
	}
	nodeArray = nodeArray.reverse();
	return nodeArray;
}

function findSiblingOrgs(node) {
	return findOrgUnit(node.parent_ou()).children();
}


function grabCopyLocations() {

	if(globalCopyLocations != null) return;
	debug("Grabbing copy locations");

	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.config.copy_location.retrieve.all" );

	req.send(true);
	globalCopyLocations = req.getResultObject();
	return globalCopyLocations;

}

function findCopyLocation(id) {

	grabCopyLocations();
	if(typeof id == 'object') return id;

	if(globalCopyLocations == null) 
		throw new EXLogic("globalCopyLocations is NULL");

	for( var x = 0; x!= globalCopyLocations.length; x++) {
		if(globalCopyLocations[x].id() == id)
			return globalCopyLocations[x];
	}
	return null;
}


