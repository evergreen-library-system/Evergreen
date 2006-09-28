var oilsRptFolderNodeCache = {};
oilsRptFolderNodeCache.template = {};
oilsRptFolderNodeCache.report  = {};
oilsRptFolderNodeCache.output  = {};

oilsRptSetSubClass('oilsRptFolderManager','oilsRptObject');

function oilsRptFolderManager() {
	this.folderTree = {};
	this.super.init();
	this.tId = oilsNextId();
	this.rId = oilsNextId();
	this.oId = oilsNextId();
	this.stId = oilsNextId();
	this.srId = oilsNextId();
	this.soId = oilsNextId();
	this.orgTrail = {};
	this.orgTrail.template = {};
	this.orgTrail.report = {};
	this.orgTrail.output = {};
}

oilsRptFolderManager.prototype.draw = function(auth) {
	oilsRptTemplateFolderTree = new SlimTree(DOM.oils_rpt_template_folder_tree, 'oilsRptTemplateFolderTree');
	oilsRptTemplateFolderTree.addNode(this.tId, -1, 'Templates')

	oilsRptReportFolderTree = new SlimTree(DOM.oils_rpt_report_folder_tree, 'oilsRptReportFolderTree');
	oilsRptReportFolderTree.addNode(this.rId, -1, 'Reports')

	oilsRptOutputFolderTree = new SlimTree(DOM.oils_rpt_output_folder_tree, 'oilsRptOutputFolderTree');
	oilsRptOutputFolderTree.addNode(this.oId, -1, 'Output')

	oilsRptSharedTemplateFolderTree = new SlimTree(DOM.oils_rpt_template_shared_folder_tree, 'oilsRptSharedTemplateFolderTree');
	oilsRptSharedTemplateFolderTree.addNode(this.stId, -1, 'Templates')

	oilsRptSharedReportFolderTree = new SlimTree(DOM.oils_rpt_report_shared_folder_tree, 'oilsRptSharedReportFolderTree');
	oilsRptSharedReportFolderTree.addNode(this.srId, -1, 'Reports')

	oilsRptSharedOutputFolderTree = new SlimTree(DOM.oils_rpt_output_shared_folder_tree, 'oilsRptSharedOutputFolderTree');
	oilsRptSharedOutputFolderTree.addNode(this.soId, -1, 'Output')

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
	var tree;

	folders = folders.sort(
		function(a,b) {
			var asw = a.share_with().id();
			var bsw = b.share_with().id();
			if( asw ) asw = findOrgDepth(findOrgUnit(asw));
			else asw = -1;
			if( bsw ) bsw = findOrgDepth(findOrgUnit(bsw));
			else bsw = -1;
			if( asw < bsw ) return 1;
			if( asw > bsw ) return -1;
			return 0;
		}
	);


	for( var i = 0; i < folders.length; i++ ) {
		var folder = folders[i];
		var id = oilsNextId();
		var node = { folder : folder, treeId : id };
		oilsRptFolderNodeCache[type][folder.id()] = node;
		node.folderWindow = new oilsRptFolderWindow(type, folder.id())
	}


	for( var i = 0; i < folders.length; i++ ) {

		var folder = folders[i];
		_debug(js2JSON(folder));
		var mine = (folder.owner().id() == USER.id());
		var pid;
		var treename;

		switch(type) {
			case 'template': 
				if(mine) {
					tree = oilsRptTemplateFolderTree;
					treename = 'oilsRptTemplateFolderTree';
					pid = this.tId;
				} else {
					tree = oilsRptSharedTemplateFolderTree;
					treename = 'oilsRptSharedTemplateFolderTree';
					pid = this.stId;
				}
				break;
			case 'report': 
				if(mine) {
					tree = oilsRptTemplateFolderTree;
					treename = 'oilsRptTemplateFolderTree';
					pid = this.rId;
				} else {
					tree = oilsRptSharedTemplateFolderTree;
					treename = 'oilsRptSharedTemplateFolderTree';
					pid = this.srId;
				}
				break;
			case 'output': 
				if(mine) {
					tree = oilsRptTemplateFolderTree;
					treename = 'oilsRptTemplateFolderTree';
					pid = this.oId;
				} else {
					tree = oilsRptSharedTemplateFolderTree;
					treename = 'oilsRptSharedTemplateFolderTree';
					pid = this.soId;
				}
		}

		if(!mine) {
			if(!this.orgTrail[type][folder.share_with().id()]) {
				tree.addNode(id, pid, folder.share_with().shortname());
				tree.close(pid);
				pid = id;
				id = oilsNextId();
				this.orgTrail[type][folder.share_with().id()] = pid;
			} else {
				pid = this.orgTrail[type][folder.share_with().id()];
				id = oilsNextId();
			}
		}

		if( folder.parent() ) 
			pid = this.findNode(type, folder.parent()).treeId;

		var action = 'javascript:oilsRptObject.find('+
			node.folderWindow.id+').draw();'+treename+'.toggle("'+id+'");';
		_debug('adding node '+folder.name()+' pid = '+pid);
		tree.addNode(id, pid, folder.name(), action);
		tree.close(pid);
	}
}


/*
oilsRptFolderManager.prototype.drawFolders = function(type, folders) {
	this.folderTree[type] = { children : [] };
	this.makeTree(type, folders, this.folderTree[type], -1 );
}
oilsRptFolderManager.prototype.makeTree = function(type, folders, node, parentId, tree) {
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

		node.folderWindow = oilsRptBuildFolderWindow(type, node.folder.id());

		var action = 'javascript:oilsRptObject.find('+node.folderWindow.id+').draw();'+
			'oilsRptFolderTree.toggle("'+id+'");';

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
*/


oilsRptFolderManager.prototype.findNode = function(type, id) {
		_debug('finding : type = ' + type + ' : ' + id);
	return oilsRptFolderNodeCache[type][id];
}







