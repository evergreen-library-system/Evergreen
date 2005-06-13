/* Top level widget class */

/* Generic HTML container box. */

function Box() {}

/* default to no sorting and allowing dups  */
Box.prototype.init = function(title, hidden, noDups, maxItems) {

	this.node = createAppElement("div");
	this.contentNode = createAppElement("div");
	this.title(title);

	add_css_class(this.node, "box");
	add_css_class(this.contentNode, "box_content");
	this.node.appendChild(this.contentNode);

	this.items			= new Array();
	this.itemCount		= new Array();
	this.sortCounts	= false;
	this.sortKeys		= false;
	this.dup				= true;

	this.noDup(noDups);
	this.setMax(maxItems);
	this.setHidden(hidden);
}

/* top level box title */
Box.prototype.title = function(title) {
	if(title == null) return;
	this.titleNode = createAppElement("div");
	add_css_class(this.titleNode, "box_title");
	this.titleNode.appendChild(createAppTextNode(title));
	this.node.insertBefore(this.titleNode, this.node.firstChild);
	return this;
}

Box.prototype.hideOnEmpty = function() {
	this.hideOnEmpty = true;
}

Box.prototype.addFooter = function(domItem) {
	this.footerNode = createAppElement("div")
	add_css_class(this.footerNode, "box_footer");
	this.footerNode.appendChild(domItem);
	this.contentNode.appendChild(this.footerNode);
}

/* add a caption below the title */
Box.prototype.addCaption = function(caption) {
	alert(this.node.name);
	if(caption == null) return;
	var captionNode = createAppElement("div");
	add_css_class(captionNode, "box_caption");
	captionNode.appendChild(createAppTextNode(caption));
	this.node.insertBefore(captionNode, this.contentNode);
}


Box.prototype.setHidden = function(bool) {
	this.hidden = bool;
	if( bool ) {
		add_css_class( this.node, "hide_me" );
		remove_css_class( this.node, "show_me" );
	} else {
		add_css_class( this.node, "show_me" );
		remove_css_class( this.node, "hide_me" );
	}
}


Box.prototype.addItem = function(domItem, key) {
	var boxItem = new BoxItem();
	boxItem.init(domItem, key);
	this.addRestrictDups(boxItem,key);
}

/* only restricts dups if necessary. */
Box.prototype.addRestrictDups = function(boxItem, key) {

	if(key) { /* check for dups */

		if(this.itemCount[key] == null)
			this.itemCount[key] = 0;
		this.itemCount[key] += 1;

		var found = false;
	
		/* uniquify */
		if(!this.dup) {
			for( var index in this.items ) {
				if(this.items[index].key == key) {
					found = true; break;
				}
			}
		}
	
		/* append the new item */
		if(!found) 
			this.append(boxItem.getNode());
		this.items.push(boxItem);

	} else { 
		/* just append it */
		this.append(boxItem.getNode());
	}

}

Box.prototype.append = function(domItem) {
	this.contentNode.appendChild(domItem);
}

Box.prototype.remove = function(domItem) {
	this.contentNode.removeChild(domItem);
}


Box.prototype.sortByCount = function() {
	this.sortCounts = true;
	this.sortKeys	= false;
}

Box.prototype.sortByKey	= function() {
	this.sortCounts = false;
	this.sortKeys	= true;
}

Box.prototype.noDup	= function() {
	this.dup = false;
}

Box.prototype.getNode = function() {
	return this.node;
}

Box.prototype.setMax = function(max) {
	if(max != null && max > -1)
		this.max = max;
	else
		this.max = null;
}

Box.prototype.sortMyKeys = function() {

	var keys = new Array();

	for( var i in this.items) 
		keys.push(this.items[i].getKey());

	keys = keys.sort();
	debug("Keys: " + keys);

	/* drop all of the children */
	while(this.contentNode.childNodes.length > 0 ) 
		this.contentNode.removeChild(
				this.contentNode.lastChild);

	for(var k in keys) {
		var node = this.findByKey(keys[k]);
		if(node)
			this.contentNode.appendChild(node.getNode());
	}

}


Box.prototype.sortMyCounts = function() {

	var counts = new Array();
	for( var x in this.itemCount) {
		counts.push(this.itemCount[x]);
	}


	/* remove all of the divs */
	while(this.contentNode.childNodes.length > 0 ) 
		this.contentNode.removeChild(
				this.contentNode.lastChild);

	/* then re-insert in order of the sorted counts array*/
	counts = counts.sort().reverse();
	for(var i in counts) {
		for( var c in this.itemCount ) {
			if(this.itemCount[c] == counts[i]) {
				var item = this.findByKey(c);
				this.contentNode.appendChild(item.getNode());
			}
		}
	}

}


Box.prototype.sortMyBoth = function() {
}

Box.prototype.findByKey = function(key) {
	for( var i in this.items) {
		if( this.items[i] && this.items[i].getKey() == key)
			return this.items[i];
	}
	return null;
}

/* removes the given item from this box and returns the item */
Box.prototype.removeItem = function(key) {
	for( var i in this.items) {
		if( this.items[i] && this.items[i].getKey() == key) {
			var obj = this.items[i];
			this.remove(obj.getNode());

			/* scooch all the other items down by one */
			for( var j = i; j!= this.items.length; j++ ) {
				this.items[j] = this.items[j+1];
			}
			return obj;
		}
	}
	return null;
}

/* checks for sorting order/max items and does the final 
	div drawing. Sets hidden to false */
Box.prototype.finalize = function() {

	/* first sort if necessary */

	if(this.sortCounts && this.sortKeys)
		this.sortMyBoth(); 

	else if(this.sortKeys)
		this.sortMyKeys();

	else if(this.sortCounts) 
		this.sortMyCounts();

	/* then trim */
	if( this.max ) {
		while(this.contentNode.childNodes.length > this.max ) 
			this.contentNode.removeChild(this.contentNode.lastChild);
	}

	/* only display the box if there is data inside */
	//if(this.contentNode.childNodes.length > 0)
	if( this.items.length  > 0 )
		this.setHidden(false);
}


/* ---------------------------------------------------- */
function BoxItem() {}

/* if listItem, we put everything into an 'li' block */
BoxItem.prototype.init = function(domItem, key) {

	this.item = domItem;
	this.key  = key;

	this.node = createAppElement("div");
	this.node.appendChild(domItem);

	add_css_class( this.node, "box_item" );
}

BoxItem.prototype.getNode = function() {
	return this.node;
}

BoxItem.prototype.getKey = function() {
	return this.key;
}



