var oilsRptFolderNodeCache = {};

function oilsRptFolderManager(node) {
	this.node = node;
	this.folderTree = {};
}

oilsRptFolderManager.prototype.draw = function(auth) {
	var tree = oilsRptFolderTree = 
		new SlimTree(this.node, 'oilsRptFolderTree');

	this.rootTreeId		= oilsNextId();
	this.templateTreeId	= oilsNextId();
	this.reportTreeId		= oilsNextId();
	this.outputTreeId		= oilsNextId();

	tree.addNode(this.rootTreeId, -1, 'Report Folders');
	tree.addNode(this.templateTreeId, this.rootTreeId, 'Template Folders');
	tree.addNode(this.reportTreeId, this.rootTreeId, 'Report Folders');
	tree.addNode(this.outputTreeId, this.rootTreeId, 'Output Folders');

	this.fetchFolders(auth);
}

oilsRptFolderManager.prototype.fetchFolders = function(auth) {
	var obj = this;
	var req = new Request(OILS_RPT_FETCH_FOLDERS, auth, 'template');
	req.callback( function(r) { obj.drawFolders('template', r.getResultObject()); } );
	req.send();

	var req = new Request(OILS_RPT_FETCH_FOLDERS, auth, 'report');
	req.callback( function(r) { obj.drawFolders('report', r.getResultObject()); } );
	req.send();

	var req = new Request(OILS_RPT_FETCH_FOLDERS, auth, 'output');
	req.callback( function(r) { obj.drawFolders('output', r.getResultObject()); } );
	req.send();
}


oilsRptFolderManager.prototype.drawFolders = function(type, folders) {
	_debug('making folder tree '+type);
	switch(type) {
		case 'template': tid = this.templateTreeId; break;
		case 'report': tid = this.reportTreeId; break;
		case 'output': tid = this.outputTreeId; break;
	}
	this.folderTree[type] = { children : [] };
	this.makeTree(type, folders, this.folderTree[type], tid );
}


/* builds an in-memory version of the folder trees as well as the UI trees */
oilsRptFolderManager.prototype.makeTree = function(type, folders, node, parentId) {
	if(!node) return;
	var id = parentId;
	var childNodes;

	if( ! node.folder ) {
		childNodes = grep(folders, function(f){return (!f.parent())});

	} else {
		_debug("making subtree with folder "+node.folder.name());

		var c = oilsRptFolderNodeCache;
		if(!c[type]) c[type] = {};
		c[type][node.folder.id()] = node;

		id = oilsNextId();

		var action = 'javascript:oilsRptDrawFolderWindow("'+
			type+'","'+node.folder.id()+'");oilsRptFolderTree.toggle("'+id+'");';

		oilsRptFolderTree.addNode(id, parentId, node.folder.name(), action);
		node.treeId = id;
		node.children = [];
		childNodes = grep(folders, 
			function(i){return (i.parent() == node.folder.id())});
	} 

	if(!childNodes) return;
	for( var i = 0; i < childNodes.length; i++ ) 
		this.makeTree( type, folders, { folder : childNodes[i] }, id );
}

oilsRptFolderManager.prototype.findNode = function(type, id) {
	return oilsRptFolderNodeCache[type][id];
}






