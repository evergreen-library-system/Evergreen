/* */

function LocationTree( tree ) {
	this.orgTree = tree;
}

LocationTree.prototype.buildOrgTreeWidget = function(org_node) {

	var item;

	if(org_node == null) {
		org_node = this.orgTree;
		item = new WebFXTree(org_node.name());
		this.widget = item;
		item.setBehavior('classic');
	} else {
		item = new WebFXTreeItem(org_node.name());
	}

	item.action = "javascript:globalPage.updateSelectedLocation('" + org_node.id() + "');";

	for( var index in org_node.children()) {
		var childorg = org_node.children()[index];
		if( childorg != null ) {
			var tree_node = buildOrgTreeWidget(childorg);
			if(tree_node != null)
				item.add(tree_node);
		}
	}
}


LocationTree.prototype.hide = function() {
	/*
	if(this.treeContainerBox &&  
			this.treeContainerBox.className.indexOf("nav_bar_visible") != -1 ) {
		swapClass( this.treeContainerBox, "nav_bar_hidden", "nav_bar_visible" );
	}
	*/
}

LocationTree.prototype.toggle = function(button_div, offsetx, offsety) {

	this.treeContainerBox = getById("ot_nav_widget");
	this.treeBox = getById("ot_nav_widget_box");
	debug("Tree container " + this.treeContainerBox );
	debug("Tree box " + this.treeBox );
	swapClass( this.treeContainerBox, "nav_bar_hidden", "nav_bar_visible" );

	if(this.treeBox && this.treeBox.firstChild.nodeType == 3) {
		setTimeout("renderTree()", 5 );
	}

	if( button_div && !offsetx && !offsety) {
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


function renderTree() {

	globalPage.locationTree.treeContainerBox = getById("ot_nav_widget");
	globalPage.locationTree.treeBox = getById("ot_nav_widget_box");

	if(!globalPage.locationTree.widget)
		globalPage.locationTree.buildOrgTreeWidget(); 
	globalPage.locationTree.treeBox.innerHTML = 
		globalPage.locationTree.widget.toString();

}


