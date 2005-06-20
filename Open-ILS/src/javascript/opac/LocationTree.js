/* */

function LocationTree( tree, box_id, container_id ) {
	this.orgTree = tree;

	this.treeContainerBoxId = container_id;
	this.treeBoxId = box_id;
	this.setObjects();
}


LocationTree.prototype.setObjects = function() {
	if(this.treeContainerBoxId)
		this.treeContainerBox = getById(this.treeContainerBoxId);
	else
		this.treeContainerBox = getById("ot_nav_widget");

	if(this.treeBoxId)
		this.treeBox = getById(treeBoxId);
	else
		this.treeBox = getById("ot_nav_widget_box");

}

LocationTree.prototype.buildOrgTreeWidget = function() {

	debug("Somebody called buildOrgTreeWidget on me...");
	this.setObjects();
	this.widget = buildOrgTreeWidget(globalOrgTree, true);
}


function buildOrgTreeWidget(org_node, root) {

	var item;

	if(root) {
		item = new WebFXTree(org_node.name());
		item.setBehavior('classic');
	} else {
		item = new WebFXTreeItem(org_node.name());
	}

	/* make org tree re-submit search on click */
	item.action = 
		"javascript:globalPage.updateSelectedLocation('" + org_node.id() + "');" +
		"globalPage.locationTree.hide();"; 

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


LocationTree.prototype.hide = function() {
	this.setObjects();
	this.widget = buildOrgTreeWidget(globalOrgTree, true);
	if(this.treeContainerBox &&  
			this.treeContainerBox.className.indexOf("nav_bar_visible") != -1 ) {
		swapClass( this.treeContainerBox, "nav_bar_hidden", "nav_bar_visible" );
	}
}



LocationTree.prototype.toggle = function(button_div, offsetx, offsety) {

	this.setObjects();
	debug("Tree container " + this.treeContainerBox );
	debug("Tree box " + this.treeBox );

	swapClass( this.treeContainerBox, "nav_bar_hidden", "nav_bar_visible" );

	var obj = this;
	if(this.treeBox && this.treeBox.firstChild.nodeType == 3) {
		setTimeout(function() { renderTree(obj); }, 5 );
	}


	if( button_div && offsetx == null && offsety == null ) {
		var x = findPosX(button_div);
		var y = findPosY(button_div);
		var height = getObjectHeight(button_div);
		var xpos = x - getObjectWidth(this.treeBox) + getObjectWidth(button_div);
		offsety = y + height;
		offsetx = xpos;	
	}

	if(IE) { /*HACK XXX*/
		offsety = parseInt(offsety) + 15;
		offsetx = parseInt(offsetx) + 8;
	}

	this.treeContainerBox.style.position = "absolute"; 
	this.treeContainerBox.style.top = offsety; 
	this.treeContainerBox.style.left = offsetx;
}


function renderTree(tree) {
	tree.setObjects();
	if(!tree.widget) tree.buildOrgTreeWidget(); 
	tree.treeBox.innerHTML = tree.widget.toString();
}


