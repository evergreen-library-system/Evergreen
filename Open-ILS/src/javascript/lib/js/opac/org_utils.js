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


/* returns an org unit by id.  if an object is passed in as the id,
	then the object is assumed to be an org unit and is returned */
function findOrgUnit(org_id) {
	if(org_id == null) return null;
	if(typeof org_id == 'object') return org_id;
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

