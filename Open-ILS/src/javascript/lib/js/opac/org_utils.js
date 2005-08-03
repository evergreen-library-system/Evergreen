/* takes an org unit or id and return the numeric depth */
function findOrgDepth(org_id_or_node) {

	if(org_id_or_node == null || globalOrgTypes == null)
		return null;

	var org = findOrgUnit(org_id_or_node);

	var t = findOrgType(org.ou_type());
	if(t != null) return t.depth();

	return null;
}

/* takes the org type id from orgunit.ou_type() field and returns
	the org type object */
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


/* locates a specific org unit by id, acts as a cache of orgs*/
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

/* returns an org unit by id.  if an object is passed in as the id,
	then the object is assumed to be an org unit and is returned */
function findOrgUnit(org_id, branch) {

	if(org_id == null) return null;
	if(typeof org_id == 'object') return org_id;

	/* if we don't have the global org tree, grab the org unit from the server */
	var tree_exists = false;
	try{if(globalOrgTree != null) tree_exists = true;}catch(E){}

	if(!tree_exists) {
		var org = orgArraySearcher[org_id];
		if(org) return org;
		var r = new RemoteRequest(
			"open-ils.actor",
			"open-ils.actor.org_unit.retrieve", null, org_id);
		r.send(true);
		orgArraySearcher[org_id] = r.getResultObject();
		return orgArraySearcher[org_id];
	}

	if(orgArraySearcher == null)
		_flattenOrgs();

	return orgArraySearcher[org_id];
}


/* builds a trail from the top of the org tree to the node provide.
	basically fleshes out 'my orgs' 
	Returns an array of [org0, org1, ..., myorg]
 */
function orgNodeTrail(node) {
	var nodeArray = new Array();
	while( node ) {
		nodeArray.push(node);
		node = findOrgUnit(node.parent_ou());
	}
	nodeArray = nodeArray.reverse();
	return nodeArray;
}


/* returns an array of sibling org units */
function findSiblingOrgs(node) {
	return findOrgUnit(node.parent_ou()).children();
}

