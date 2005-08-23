/* ------------------------------------------------------------------------------------------------------ */
/* org tree utilities */
/* ------------------------------------------------------------------------------------------------------ */

/* takes an org unit or id and return the numeric depth */
function findOrgDepth(org_id_or_node) {
	return findOrgType(findOrgUnit(org_id_or_node).ou_type()).depth();
}

/* takes the org type id from orgunit.ou_type() field and returns
	the org type object */
function findOrgType(type_id) {
	if(typeof type_id == 'object') return type_id;
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
	return (typeof org_id == 'object') ? org_id : orgArraySearcher[org_id];
}


/* builds a trail from the top of the org tree to the node provide.
	basically fleshes out 'my orgs' 
	Returns an array of [org0, org1, ..., myorg] */
function orgNodeTrail(node) {
	var na = new Array();
	while( node ) {
		na.push(node);
		node = findOrgUnit(node.parent_ou());
	}
	return na.reverse();
}

function findSiblingOrgs(node) { return findOrgUnit(node.parent_ou()).children(); }



var orgArraySearcher = {};
var globalOrgTree;
for (var i in _l) {
	var x = new aou();
	x.id(_l[i][0]);
	x.ou_type(_l[i][1]);
	x.parent_ou(_l[i][2]);
	x.name(_l[i][3]);
	orgArraySearcher[x.id()] = x;
}
for (var i in orgArraySearcher) {
	var x = orgArraySearcher[i];
	if (x.parent_ou() == null || x.parent_ou() == '') {
		globalOrgTree = x;
		continue;
	} 

	var parent = findOrgUnit(x.parent_ou());
	if (!parent.children()) parent.children(new Array());
	parent.children().push(x);
}

function _tree_killer () {
	for (var i in orgArraySearcher) {
		x=orgArraySearcher[i];
		x.children(null);
		x.parent_ou(null);
		orgArraySearcher[i]=null;
	}
	globalOrgTree = null;
	orgArraySearcher = null;
	globalOrgTypes = null;
}



