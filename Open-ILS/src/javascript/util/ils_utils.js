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
		if( t.id() == type_id ) 
			return t;
	}
	return null;
}


/* locates a specific org unit */
function findOrgUnit(org_id, branch) {
	if(org_id == null) return null;
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


function buildOrgTreeWidget(org_node) {

	var item;

	globalPage.treeWidgetElements = new Array();

	if(org_node == null) {
		org_node = globalOrgTree;
		item = new WebFXTree(org_node.name());
		item.setBehavior('classic');
	} else {
		item = new WebFXTreeItem(org_node.name());
	}

	item.action = "javascript:globalPage.updateSelectedLocation('" + org_node.id() + "');";
	globalPage.treeWidgetElements[item.id] = org_node;

	for( var index in org_node.children()) {
		var childorg = org_node.children()[index];
		if( childorg != null ) {
			var tree_node = buildOrgTreeWidget(childorg);
			if(tree_node != null)
				item.add(tree_node);
		}
	}

	return item;
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
		debug("pushing " + node.name() );
		nodeArray.push(node);
		node = findOrgUnit(node.parent_ou());
	}
	nodeArray = nodeArray.reverse();
	return nodeArray;
}



