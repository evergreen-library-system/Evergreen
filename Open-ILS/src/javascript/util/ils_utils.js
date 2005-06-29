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
var orgArraySearcher = null;

/* flatten the org tree for faster searching */
function _flattenOrgs(node) { 

	if(node == null) {
		node = globalOrgTree;
		orgArraySearcher = new Object();
	}

	orgArraySearcher[node.id()] = node;
	for(var idx in node.children()) {
		_flattenOrgs(node.children()[idx]);
	}
}

function findOrgUnit(org_id, branch) {
	if(org_id == null) return null;
	if(typeof org_id == 'object') return org_id;
	if(globalOrgTree == null)
		throw new EXArg("Need globalOrgTree");

	if(orgArraySearcher == null)
		_flattenOrgs();

	return orgArraySearcher[org_id];
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


function modsFormatToMARC(format) {
	switch(format) {
		case "text":
			return "at";
		case "moving image":
			return "g";
		case "sound recording":
			return "ij";
		case "software, multimedia":
			return "m";
		case "still images":
			return "k";
		case "cartographic":
			return "ef";
		case "mixed material":
			return "op";
		case "notated muix":
			return "cd";
		case "three dimensional object":
			return "r";
	}
	throw new EXLogic("Invalid format provided form modsFormatToMARC: " + format);
}


