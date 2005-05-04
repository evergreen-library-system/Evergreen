/* Top level widget class */

/* Generic HTML container box. */

ListBox.prototype					= new Box();
ListBox.prototype.constructor	= ListBox;
ListBox.baseClass					= Box.constructor;

function ListBox() {}

/* default to no sorting and allowing dups  */
ListBox.prototype.listBoxInit = 
	function(ordered, title, hidden, noDups, maxItems) {

	this.ordered = ordered;
	this.node = createAppElement("div");
	this.contentWrapperNode = createAppElement("div");
	this.node.name = "anode";

	if(this.ordered)
		this.contentNode = createAppElement("ol");
	else
		this.contentNode = createAppElement("ul");


	add_css_class(this.node, "box");
	add_css_class(this.node, "list_box");
	add_css_class(this.contentWrapperNode, "box_content");
	add_css_class(this.contentWrapperNode, "list_box_content");

	this.node.appendChild(this.contentWrapperNode);
	this.contentWrapperNode.appendChild(this.contentNode);

	this.items			= new Array();
	this.itemCount		= new Array();
	this.sortCounts	= false;
	this.sortKeys		= false;
	this.dup				= true;

	this.title(title);
	this.noDup(noDups);
	this.setMax(maxItems);
	this.setHidden(hidden);
}

/* add a caption below the title */
ListBox.prototype.addCaption = function(caption) {
	if(caption == null) return;
	var captionNode = createAppElement("div");
	add_css_class(captionNode, "box_caption");
	captionNode.appendChild(createAppTextNode(caption));
	this.node.insertBefore(captionNode, this.contentWrapperNode);
}



ListBox.prototype.addItem = function(domItem, key) {
	var boxItem = new ListBoxItem();
	boxItem.init(domItem, key);
	this.addRestrictDups(boxItem, key);
}


ListBox.prototype.addFooter = function(domItem) {
	this.footerNode = createAppElement("div");
	add_css_class(this.footerNode, "box_footer");
	this.footerNode.appendChild(domItem);
	this.contentWrapperNode.appendChild(this.footerNode);
}

ListBox.prototype.removeFooter = function() {
	if( this.footerNode != null )
		this.contentWrapperNode.removeChild(
			this.footerNode );
}


/* ---------------------------------------------------- */

ListBoxItem.prototype					= new BoxItem();
ListBoxItem.prototype.constructor	= ListBoxItem;
ListBoxItem.baseClass					= BoxItem.constructor;

function ListBoxItem() {}

ListBoxItem.prototype.init = function(domItem, key) {

	this.item = domItem;
	this.key  = key;

	this.node = createAppElement("li");
	this.contentNode = createAppElement("div");
	this.contentNode.appendChild(domItem);
	this.node.appendChild(this.contentNode);

	add_css_class( this.node, "list_box_list" );
	add_css_class( this.contentNode, "box_item" );
	add_css_class( this.contentNode, "list_box_item" );
}

