dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");

var oilsRptFolderNodeCache = {};
oilsRptFolderNodeCache.template = {};
oilsRptFolderNodeCache.report  = {};
oilsRptFolderNodeCache.output  = {};
// ephemeral template search results folder needs an ID.
var oilsRptSearchResultFolderId = -1000; 
var oilsRptSearchResultFolderWindowId = null;

oilsRptSetSubClass('oilsRptFolderManager','oilsRptObject');

function oilsRptFolderManager() { this.init(); }

oilsRptFolderManager.prototype.draw = function(auth) {

	if(!auth) auth = SESSION;

	this.folderTree = {};
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

	removeChildren(DOM.oils_rpt_template_folder_tree); 
	removeChildren(DOM.oils_rpt_report_folder_tree); 
	removeChildren(DOM.oils_rpt_output_folder_tree); 
	removeChildren(DOM.oils_rpt_template_shared_folder_tree); 
	removeChildren(DOM.oils_rpt_report_shared_folder_tree); 
	removeChildren(DOM.oils_rpt_output_shared_folder_tree); 

	var porg = PERMS.SHARE_REPORT_FOLDER;
	if( porg < 1 ) 
		DOM.oils_rpt_top_folder_shared.disabled = true;

	var obj = this;
	var orgsel = new oilsRptMyOrgsWidget(
		DOM.oils_rpt_top_folder_lib_picker, USER.ws_ou(), porg)
	orgsel.draw();

	oilsRptTemplateFolderTree = 
		new SlimTree(
			DOM.oils_rpt_template_folder_tree, 
			'oilsRptTemplateFolderTree');
			//'images/template-page.gif');

	oilsRptTemplateFolderTree.addNode(this.tId, -1, rpt_strings.FOLDERS_TEMPLATES,
		function() {
			unHideMe(DOM.oils_rpt_folder_table_alt_td);
			unHideMe(DOM.oils_rpt_top_folder);
			hideMe(DOM.oils_rpt_editor_div);
			appendClear(DOM.oils_rpt_top_folder_type,text(rpt_strings.FOLDERS_TEMPLATE));
			hideMe(DOM.oils_rpt_folder_table_right_td);
			DOM.oils_rpt_top_folder_create.onclick = function() {
				obj.createTopFolder('template', orgsel);
			}
		}
	);

	oilsRptReportFolderTree = 
		new SlimTree(
			DOM.oils_rpt_report_folder_tree, 
			'oilsRptReportFolderTree');
			//'images/report-page.gif');


	oilsRptReportFolderTree.addNode(this.rId, -1, rpt_strings.FOLDERS_REPORTS,
		function() {
			unHideMe(DOM.oils_rpt_folder_table_alt_td);
			unHideMe(DOM.oils_rpt_top_folder);
			hideMe(DOM.oils_rpt_editor_div);
			hideMe(DOM.oils_rpt_folder_table_right_td);
			appendClear(DOM.oils_rpt_top_folder_type,text(rpt_strings.FOLDERS_REPORT));
			DOM.oils_rpt_top_folder_create.onclick = function() {
				obj.createTopFolder('report', orgsel);
			}
		}
	);



	oilsRptOutputFolderTree = 
		new SlimTree(
			DOM.oils_rpt_output_folder_tree, 
			'oilsRptOutputFolderTree');
			//'images/output-page.gif');

	oilsRptOutputFolderTree.addNode(this.oId, -1, rpt_strings.FOLDERS_OUTPUT,
		function() {
			unHideMe(DOM.oils_rpt_folder_table_alt_td);
			unHideMe(DOM.oils_rpt_top_folder);
			hideMe(DOM.oils_rpt_editor_div);
			hideMe(DOM.oils_rpt_folder_table_right_td);
			appendClear(DOM.oils_rpt_top_folder_type,text(rpt_strings.FOLDERS_OUTPUT));
			DOM.oils_rpt_top_folder_create.onclick = function() {
				obj.createTopFolder('output', orgsel);
			}
		}
	);


	oilsRptSharedTemplateFolderTree = 
		new SlimTree(
			DOM.oils_rpt_template_shared_folder_tree, 
			'oilsRptSharedTemplateFolderTree');
			//'images/template-page.gif');

	oilsRptSharedTemplateFolderTree.addNode(this.stId, -1, rpt_strings.FOLDERS_TEMPLATES)


	oilsRptSharedReportFolderTree = 
		new SlimTree(
			DOM.oils_rpt_report_shared_folder_tree, 
			'oilsRptSharedReportFolderTree');
			//'images/report-page.gif');

	oilsRptSharedReportFolderTree.addNode(this.srId, -1, rpt_strings.FOLDERS_REPORTS)

	oilsRptSharedOutputFolderTree = 
		new SlimTree(
			DOM.oils_rpt_output_shared_folder_tree, 
			'oilsRptSharedOutputFolderTree');
			//'images/output-page.gif');

	oilsRptSharedOutputFolderTree.addNode(this.soId, -1, rpt_strings.FOLDERS_OUTPUT)

    DOM.template_search_submit_button.onclick = function() {
        oilsRptObject.find(oilsRptSearchResultFolderWindowId).draw();
    }

	this.fetchFolders(auth);
}

oilsRptFolderManager.prototype.createTopFolder = function(type, orgsel) {

	if( type == 'report' ) folder = new rrf();
	if( type == 'template' ) folder = new rtf();
	if( type == 'output' ) folder = new rof();

	folder.owner(USER.id());
	folder.parent(null);

	/* Protect against empty folder names */
	if (!DOM.oils_rpt_top_folder_name.value) {
		return;
	}

	folder.name(DOM.oils_rpt_top_folder_name.value);
	folder.shared(getSelectorVal(DOM.oils_rpt_top_folder_shared));

	if( folder.shared() == 't' )
		folder.share_with( orgsel.getValue() );

	oilsRptCreateFolder(folder, type,
		function(success) {
			if(success) {
				oilsRptAlertSuccess();
				oilsRptCurrentFolderManager.draw();
				hideMe(DOM.oils_rpt_top_folder);
				hideMe(DOM.oils_rpt_folder_table_alt_td);
				unHideMe(DOM.oils_rpt_editor_div);
			}
		}
	);
}


oilsRptFolderManager.prototype.fetchFolders = function(auth) {
	var obj = this;
	if(PERMS.RUN_REPORTS != -1) {
		var req = new Request(OILS_RPT_FETCH_FOLDERS, auth, 'template');
		req.callback( function(r) { obj.drawFolders('template', r.getResultObject()); } );
		req.send();

		var req = new Request(OILS_RPT_FETCH_FOLDERS, auth, 'report');
		req.callback( function(r) { obj.drawFolders('report', r.getResultObject()); } );
		req.send();
	}

	var req = new Request(OILS_RPT_FETCH_FOLDERS, auth, 'output');
	req.callback( function(r) { obj.drawFolders('output', r.getResultObject()); } );
	req.send();
}


oilsRptFolderManager.prototype.drawFolders = function(type, folders) {

	var tree;
	var owners = {};

    // Special search results folders ; not added to folder tree.
    if (type == 'template') {
        var resFolder = new rtf();
        resFolder.id(oilsRptSearchResultFolderId);
        resFolder.name(''); // not shown
        resFolder.owner(USER);
        folders.unshift(resFolder);
    }

	for( var i = 0; i < folders.length; i++ ) {

		var folder = folders[i];
		var id = oilsNextId();
		var node = { folder : folder, treeId : id };

		oilsRptFolderNodeCache[type][folder.id()] = node;
		node.folderWindow = new oilsRptFolderWindow(type, folder.id())

        if (folder.id() == oilsRptSearchResultFolderId) 
            oilsRptSearchResultFolderWindowId = node.folderWindow.id;

		/*
		_debug("creating folder node for "+folder.name()+" : id = "+
			folder.id()+' treeId = '+id + ' window id = ' + node.folderWindow.id);
			*/

		/* shared folders get a folder for the usrname of the 
			owner as the parent node for the folders in the tree */
		if(!folder.parent() && folder.owner().id() != USER.id()) {
			if(owners[folder.owner().id()]) {
				node.ownerNode = owners[folder.owner().id()];
				continue;
			}

			_debug("building usrname node "+type+" -> " +folder.owner().usrname());

			var id = oilsNextId();
			var pid = this.stId;
			var tree = oilsRptSharedTemplateFolderTree;
			var treename = 'oilsRptSharedTemplateFolderTree';

			if(type=='report') {
				tree = oilsRptSharedReportFolderTree;
				treename = 'oilsRptSharedReportFolderTree';
				pid = this.srId;
			}

			if(type=='output') {
				tree = oilsRptSharedOutputFolderTree;
				treename = 'oilsRptSharedOutputFolderTree';
				pid = this.soId;
			}

			tree.addNode(id, pid, folder.owner().usrname());
			tree.close(pid);
			owners[folder.owner().id()] = id;
			node.ownerNode = id;
		}
	}

    var search_folders = [];
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

		node = this.findNode(type, folder.id());
		id = node.treeId;
		if( folder.parent() ) {
            var pnode = this.findNode(type, folder.parent());
			if(!pnode){
                console.error("An error occurred retrieving "+type+" folder #"+folder.parent());
                continue;
            }
            pid = pnode.treeId;
            node.depth = pnode.depth + 1;
        } else {
            node.depth = 0;
        }

		var fname = folder.name();

		if(!mine) {
			fname = folder.name() + ' ('+folder.share_with().shortname()+')';
			if( node.ownerNode ) pid = node.ownerNode;

		} else {
			if(isTrue(folder.shared()))
				fname = folder.name() + ' ('+folder.share_with().shortname()+')';
		}

		var action = 'javascript:oilsRptObject.find('+node.folderWindow.id+').draw();';

		/*
		_debug('adding node '+fname+' id = ' + id + ' pid = '
			+pid + ' parent = ' + folder.parent() + ' folder-window = ' + node.folderWindow.id );
			*/

        if (folder.id() != oilsRptSearchResultFolderId) {
            search_folders.push({id : folder.id(), pid: folder.parent(), fname : fname, depth : node.depth});
		    tree.addNode(id, pid, fname, action);
		    tree.close(pid);
        }
	}

    // search only applies to templates
    if (type != 'template') return;

    // Sort the list of search folders from top to bottom of the folder tree.
    var depth_cache = {};
    function add_folder(node) {
        if (!node) return;

        var label = node.fname;
        // Left-pad the selector options by depth with U+2003 'EM SPACE'
        // characters so the browser won't collapse the space.
        for (var i = 0; i < node.depth; i++) label = ' ' + label;

        insertSelectorVal(
            DOM.template_search_folder_selector, -1, label, node.id);

        var children = search_folders.filter(
            function(f) { return (f.pid == node.id) });
        dojo.forEach(children, add_folder);
    }

    // start with the parent-less folders
    dojo.forEach(
        search_folders.filter(
            function(f) {return f.pid == null}), add_folder);
}


oilsRptFolderManager.prototype.findNode = function(type, id) {
	return oilsRptFolderNodeCache[type][id];
}






/* this only works if the initial folder tree has been drawn 
	if defined, "action" must be a function pointer that takes the
	folder node as the param 

    eachFolder - optional callback called with each folder
    node after its added to the folder list.
*/
var __someid;
function oilsRptBuildFolder(type, node, treeVar, rootName, action, shared, eachFolder) {
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

		if( !shared && (f.owner().id() != USER.id()) ) continue;
		if( f.id() == oilsRptSearchResultFolderId ) continue;

		if(f.parent()) {
			/* find the parent's tree id so we can latch on to it */
			var pnode = cache[f.parent()];
			var pid = pnode.treeId + __someid;
		}

		tree.addNode(tid, pid, f.name(), __setFolderCB(tree, tid, action, cache[c]));

        if (eachFolder) eachFolder(cache[c]);
	}
	eval(treeVar +' = tree;');
}

function __setFolderCB(tree, id, action, node) {
	var act;
	if( action ) 
		act = function() { action( node ); };
	return act;
}

