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

	this.ownerFolders = {};
	this.ownerFolders.template = {};
	this.ownerFolders.report = {};
	this.ownerFolders.output = {};
}

oilsRptFolderManager.prototype.draw = function(auth) {

	oilsRptTemplateFolderTree = 
		new SlimTree(
			DOM.oils_rpt_template_folder_tree, 
			'oilsRptTemplateFolderTree');
			//'images/template-page.gif');

	oilsRptTemplateFolderTree.addNode(this.tId, -1, 'Templates')

	oilsRptReportFolderTree = 
		new SlimTree(
			DOM.oils_rpt_report_folder_tree, 
			'oilsRptReportFolderTree');
			//'images/report-page.gif');

	oilsRptReportFolderTree.addNode(this.rId, -1, 'Reports')


	oilsRptOutputFolderTree = 
		new SlimTree(
			DOM.oils_rpt_output_folder_tree, 
			'oilsRptOutputFolderTree');
			//'images/output-page.gif');

	oilsRptOutputFolderTree.addNode(this.oId, -1, 'Output')

	oilsRptSharedTemplateFolderTree = 
		new SlimTree(
			DOM.oils_rpt_template_shared_folder_tree, 
			'oilsRptSharedTemplateFolderTree');
			//'images/template-page.gif');

	oilsRptSharedTemplateFolderTree.addNode(this.stId, -1, 'Templates')

	oilsRptSharedReportFolderTree = 
		new SlimTree(
			DOM.oils_rpt_report_shared_folder_tree, 
			'oilsRptSharedReportFolderTree');
			//'images/report-page.gif');

	oilsRptSharedReportFolderTree.addNode(this.srId, -1, 'Reports')

	oilsRptSharedOutputFolderTree = 
		new SlimTree(
			DOM.oils_rpt_output_shared_folder_tree, 
			'oilsRptSharedOutputFolderTree');
			//'images/output-page.gif');

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
			var asw = a.share_with();
			var bsw = b.share_with();
			if( asw ) asw = findOrgDepth(findOrgUnit(asw.id()));
			else asw = -1;
			if( bsw ) bsw = findOrgDepth(findOrgUnit(bsw.id()));
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
		_debug("creating folder node for "+folder.name()+" : id = "+folder.id()+' treeId = '+id);
	}


	for( var i = 0; i < folders.length; i++ ) {

		var folder = folders[i];
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

		id = this.findNode(type, folder.id()).treeId;
		if( folder.parent() ) 
			pid = this.findNode(type, folder.parent()).treeId;


		/*
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
		*/

		var fname = folder.name();

		if(!mine) {
			fname = folder.name() + ' ('+folder.share_with().shortname()+')';
			if(!this.ownerFolders[type][folder.owner().id()]) {
				tree.addNode(id, pid, folder.owner().usrname());
				tree.close(pid);
				pid = id;
				id = oilsNextId();
				this.ownerFolders[type][folder.owner().id()] = pid;
			} else {
				pid = this.ownerFolders[type][folder.owner().id()];
				id = oilsNextId();
			}
		} else {
			if(isTrue(folder.shared()))
				fname = folder.name() + ' ('+folder.share_with().shortname()+')';
		}

		var action = 'javascript:oilsRptObject.find('+
			node.folderWindow.id+').draw();'+treename+'.toggle("'+id+'");';

		_debug('adding node '+fname+' id = ' + id + ' pid = '+pid + ' parent = ' + folder.parent() );

		tree.addNode(id, pid, fname, action);
		tree.close(pid);
	}
}


oilsRptFolderManager.prototype.findNode = function(type, id) {
	return oilsRptFolderNodeCache[type][id];
}






/* this only works if the initial folder tree has been drawn 
	if defined, "action" must be a function pointer that takes the
	folder node as the param */
var __someid;
function oilsRptBuildFolder(type, node, treeVar, rootName, action) {
	removeChildren(node);
	var tree = new SlimTree(node, treeVar);
	this.treeId = oilsNextId();
	tree.addNode(this.treeId, -1, rootName);

	__someid = oilsNextId();

	var cache = oilsRptFolderNodeCache[type];

	for( var c in cache ) {
		var tid = cache[c].treeId + __someid;
		var pid = this.treeId;
		var f = cache[c].folder;

		if(f.parent()) {
			/* find the parent's tree id so we can latch on to it */
			var pnode = cache[f.parent()];
			var pid = pnode.treeId + __someid;
		}

		tree.addNode(tid, pid, f.name(), __setFolderCB(tree, tid, action, cache[c]));
	}
	eval(treeVar +' = tree;');
}

function __setFolderCB(tree, id, action, node) {
	var act;
	if( action ) 
		act = function() { tree.toggle(id);	action( node ); };
	return act;
}

