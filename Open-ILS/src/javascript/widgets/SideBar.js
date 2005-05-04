SidebarBox.prototype					= new Box();
SidebarBox.prototype.constructor	= SidebarBox;
SidebarBox.baseClass					= Box.constructor;

function SidebarBoxItem(domItem) {
	this.node = createAppElement("div");
	var br = createAppElement("br");
	add_css_class(this.node, "sibebar_item");
	this.node.appendChild(domItem);
	this.node.appendChild(br);
}

SidebarBoxItem.prototype.getNode = function() {
	return this.node;
}

/* --------------------------------------------------------- */

function SidebarBox(title) {
	this.node = createAppElement("div");
	this.contentNode = createAppElement("div");
	this.titleNode = createAppElement("div");

	add_css_class(this.node, "sidebar_box");
	add_css_class(this.contentNode, "sidebar_content_box");
	add_css_class(this.titleNode, "sidebar_title_box");

	/* push the title in */
	this.titleNode.appendChild(createAppTextNode(title));
	this.titleNode.appendChild(createAppElement("br"));

	this.node.appendChild(this.titleNode);
	this.node.appendChild(this.contentNode);
}

SidebarBox.prototype.addItem = function(domItem) {
	this.contentNode.appendChild(new SidebarBoxItem(domItem).getNode());
}

SidebarBox.prototype.getNode = function() {
	return this.node;
}


/* --------------------------------------------------------- */

Sidebar.prototype					= new Box();
Sidebar.prototype.constructor	= Sidebar;
Sidebar.baseClass					= Box.constructor;

function Sidebar() {
	this.boxinit();
}

Sidebar.prototype.addItem = function(sidebarBox) {
	this.node.appendChild(sidebarBox.getNode());	
	this.node.innerHTML += "<br/>";
}

Sidebar.prototype.getNode = function() {
	return this.node;
}
