/* */

function LocationTree( tree, box_id, container_id ) {
	this.orgTree = tree;

	this.treeContainerBoxId = container_id;
	this.treeBoxId = box_id;
	this.setObjects();
	this.treeBuilder = buildOrgTreeWidget;
}


LocationTree.prototype.setObjects = function() {
	if(this.treeContainerBoxId)
		this.treeContainerBox = getById(this.treeContainerBoxId);
	else
		this.treeContainerBox = getById("ot_nav_widget");

	if(this.treeBoxId)
		this.treeBox = getById(this.treeBoxId);
	else
		this.treeBox = getById("ot_nav_widget_box");

}

LocationTree.prototype.buildOrgTreeWidget = function() {

	debug("Somebody called buildOrgTreeWidget on me...");
	this.setObjects();
	//this.widget = buildOrgTreeWidget(globalOrgTree, true);
	this.widget = this.treeBuilder(globalOrgTree, true);
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
	this.widget = this.treeBuilder(globalOrgTree, true);
	if(this.treeContainerBox &&  
			this.treeContainerBox.className.indexOf("show_me") != -1 ) {
		swapClass( this.treeContainerBox, "hide_me", "show_me" );
	}
}



LocationTree.prototype.toggle = function(button_div, offsetx, offsety, relative) {

	this.setObjects();
	debug("Tree container " + this.treeContainerBox );
	debug("Tree box " + this.treeBox );

	swapClass( this.treeContainerBox, "hide_me", "show_me" );

	var obj = this;
	if( (this.treeBox && this.treeBox.firstChild && 
			this.treeBox.firstChild.nodeType == 3) ||
			(!this.treeBox.firstChild)) {

		debug("location tree has not been rendered... rendering..");
		setTimeout(function() { renderTree(obj); }, 5 );
	}

	//alert(this.treeBox.firstChild.nodeType);

	if( button_div && 
			((offsetx == null && offsety == null) || relative) ) {

		var x = findPosX(button_div);
		var y = findPosY(button_div);
		var height = getObjectHeight(button_div);
		var xpos = x - getObjectWidth(this.treeBox) + getObjectWidth(button_div);

		if(offsety == null) offsety = 0;
		if(offsetx == null) offsetx = 0;

		offsety = y + height + offsety;
		offsetx = xpos + offsetx;	
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
	/*
	debug("Spitting tree out to the treeBox:\n" +
			tree.widget.toString() ); */
	tree.treeBox.innerHTML = tree.widget.toString();
}



/* generates a new chunk within with the tree is inserted */
LocationTree.prototype.newSpot = function(box_id, container_id) {

	var cont 			= elem("div", { id : this.treeContainerBoxId } );
	var box				= elem("div", { id : this.treeBoxId } );
	var expando_line 	= elem("div");
	var expando 		= elem("div");
	var expand_all		= elem("a", null, null, "Expand All");
	var collapse_all	= elem("a", null, null, "Collapse All");

	add_css_class(cont, "nav_widget");
	add_css_class(cont, "hide_me");
	add_css_class(box, "ot_nav_widget_box");
	add_css_class(expando_line, "expando_links");
	add_css_class(expando, "expando_links");


	cont.appendChild(expando_line);
	cont.appendChild(expando);
	cont.appendChild(elem("br"));
	cont.appendChild(box);

	expando_line.appendChild(elem("br"));
	var obj = this;
	expand_all.onclick = function() { obj.widget.expandAll(); };
	collapse_all.onclick = function() {
   	obj.widget.collapseAll();
		obj.widget.expand(); };

	expando.appendChild(expand_all);
	expando.appendChild(createAppTextNode(" "));
	expando.appendChild(collapse_all);
	expando.appendChild(createAppTextNode(" "));

	return cont;

}
