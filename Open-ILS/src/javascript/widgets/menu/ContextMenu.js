/*  */

/* menu item class */
function ContextMenuItem(text,onclick) {
	this.onclick = onclick;
	this.div = createAppElement("div");
	this.div.appendChild(createAppTextNode(text));
	this.div.onclick = this.onclick;
	this.div.className = "context_menu_item";


	/* add mouseover effects */
	var div = this.div;
	this.div.onmouseover = function() {
			add_css_class(div,"context_menu_item_hover");
	}
	this.div.onmouseout = function() {
		remove_css_class(div,"context_menu_item_hover");
   }

}


/* returns the DOM object (div) this item sits in */
ContextMenuItem.prototype.getNode = function() {
	return this.div;
}

/* put an image to the left of the menu item */
ContextMenuItem.prototype.addIcon= function(url) {
	var img = createAppElement("img");
	add_css_class( img, "context_menu_item_img");
	img.setAttribute("src", url);
	this.div.insertBefore( img, this.div.firstChild )
}


/* context menu class */
function ContextMenu(name) {
	this.div = createAppElement("div");
	this.wrapperDiv = createAppElement("div");
	this.wrapperDiv.appendChild(this.div);
	this.div.className = "context_menu hide_me";
	this.name = name;
	this.items = new Array();
}


/* onclick is an actual function(){...} function */
ContextMenu.prototype.addItem = function(text,onclick) {
	var item = new ContextMenuItem(text, onclick);
	this.items.push(item)
	this.div.appendChild(item.getNode());
}

/* returns the DOM object (div) this menu sits in */
ContextMenu.prototype.getNode = function() {
	return this.div;
}

/* hides this context menu */
ContextMenu.prototype.hideMe = function() {
	if( this.div.className.indexOf("show_me") != -1 ) {
		swapClass(this.div,"show_me", "hide_me");
	}
}

/* displays this context menu */
ContextMenu.prototype.showMe = function() {
	if( this.div.className.indexOf("hide_me") != -1 ) {
		swapClass(this.div,"show_me", "hide_me");
	}
}


/* if hidden, displays, and vice versa */
ContextMenu.prototype.toggle = function() {

	var mousepos =  getMousePos();
	this.div.style.position = "absolute";
   this.div.style.left = mousepos[0];
   this.div.style.top = mousepos[1];

	swapClass(this.div,"show_me", "hide_me");
}

/* returns the menu as an HTML string */
ContextMenu.prototype.toSring = function() {
	return this.wrapperDiv.innerHTML;
}

/* returns an array of ContextMenuItem objects */
ContextMenu.prototype.getItems = function() {
	return this.items;
}


