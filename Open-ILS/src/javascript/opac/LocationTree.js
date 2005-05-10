/* */

function LocationTree( tree ) {
	this.orgTree = tree;
}

LocationTree.prototype.buildOrgTreeWidget = function() {

	this.widget = buildOrgTreeWidget();
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

	/* make org tree re-submit search on click */
	item.action = 
		"javascript:globalPage.updateSelectedLocation('" + org_node.id() + "');" +
		"globalPage.locationTree.hide();"; 

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


LocationTree.prototype.hide = function() {
	this.treeContainerBox = getById("ot_nav_widget");
	if(this.treeContainerBox &&  
			this.treeContainerBox.className.indexOf("nav_bar_visible") != -1 ) {
		swapClass( this.treeContainerBox, "nav_bar_hidden", "nav_bar_visible" );
	}
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


function renderTree() {

	globalPage.locationTree.treeContainerBox = getById("ot_nav_widget");
	globalPage.locationTree.treeBox = getById("ot_nav_widget_box");

	if(!globalPage.locationTree.widget)
		globalPage.locationTree.buildOrgTreeWidget(); 
	globalPage.locationTree.treeBox.innerHTML = 
		globalPage.locationTree.widget.toString();

}


