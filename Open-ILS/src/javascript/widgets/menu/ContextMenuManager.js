/* */

function ContextMenuManager() {}

/* builds a new menu and stores it */
ContextMenuManager.prototype.buildMenu = function(name) {

	if(!this.menus) { 
		this.menus = new Array();
		/* here we hijack the body onclick to 
			hide menus that may be visible */
		getDocument().body.onclick = function() {
			globalMenuManager.hideAll(); 
		}
	}

	if(name == null) name = new Date().getTime();
	this.menus[name] = new ContextMenu(name);
	return this.menus[name];
}

/* returns the menu with the given name */
ContextMenuManager.prototype.getMenu = function(name) {
	return this.menus[name];
}

/* hides all visible menus and brings the 
	selected menu to the front */
ContextMenuManager.prototype.toggle = function(name) {
	this.hideAll();
	this.getMenu(name).toggle();
}

/* hides all menues */
ContextMenuManager.prototype.hideAll = function() {
	for( var index in this.menus) {
		this.menus[index].hideMe();
	}
}

/* sets a context object for the given menu.  When a user clicks
	in the context area, the menu appears */
ContextMenuManager.prototype.setContext = function(node, menu) {
	var obj = this;
	node.oncontextmenu = function(evt) {
		var win = getAppWindow();
		if(!win.event) win.event = evt;
		obj.toggle(menu.name);
		return false;
	}
}
