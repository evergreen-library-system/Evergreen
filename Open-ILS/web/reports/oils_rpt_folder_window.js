dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");
var OILS_TEMPLATE_INTERFACE = 'xul/template_builder.xul';
var OILS_LEGACY_TEMPLATE_INTERFACE = 'oils_rpt_builder.xhtml';


/* generic folder window class */
oilsRptSetSubClass('oilsRptFolderWindow', 'oilsRptObject');
function oilsRptFolderWindow(type, folderId) { 
	this.init();
	var node = oilsRptCurrentFolderManager.findNode(type, folderId);
	this.selector = DOM.oils_rpt_folder_contents_selector;
	this.folderNode = node;
	this.type = type;
}


oilsRptFolderWindow.prototype.draw = function() {

	_debug('drawing folder window for ' + this.folderNode.folder.name() );

	var obj = this;
	setSelector(DOM.oils_rpt_output_limit_selector, oilsRptOutputLimit);
	setSelector(DOM.oils_rpt_output_limit_selector_2, oilsRptOutputLimit2);

	DOM.oils_rpt_output_limit_selector.onchange = function() {
		oilsRptOutputLimit = getSelectorVal(DOM.oils_rpt_output_limit_selector);
		obj.draw();
	}

	DOM.oils_rpt_output_limit_selector_2.onchange = function() {
		oilsRptOutputLimit2 = getSelectorVal(DOM.oils_rpt_output_limit_selector_2);
		obj.draw();
	}

	var mine = ( this.folderNode.folder.owner().id() == USER.id() );

	_debug('drawing folder window with type '+this.type);
	if(mine) _debug('folder is mine...');

	if( mine && this.type == 'template') 
		unHideMe(DOM.oils_rpt_folder_window_contents_new_template.parentNode);
	else hideMe(DOM.oils_rpt_folder_window_contents_new_template.parentNode);

	unHideMe(DOM.oils_rpt_folder_window_contents_div);
	hideMe(DOM.oils_rpt_folder_manager_div);
	hideMe(DOM.oils_rpt_top_folder);

	DOM.oils_rpt_folder_window_manage_tab.onclick = function() {
		unHideMe(DOM.oils_rpt_folder_window_contents_div);
		hideMe(DOM.oils_rpt_folder_manager_div);
	}
	DOM.oils_rpt_folder_window_edit_tab.onclick = function() {
		hideMe(DOM.oils_rpt_folder_window_contents_div);
		unHideMe(DOM.oils_rpt_folder_manager_div);
	}

	this.setFolderEditActions();

	hideMe(DOM.oils_rpt_template_folder_new_report);
	unHideMe(DOM.oils_rpt_folder_table_right_td);
	hideMe(DOM.oils_rpt_folder_table_alt_td);
	this.drawFolderDetails();

	DOM.oils_rpt_folder_content_action_go.onclick = 
		function() {obj.doFolderAction()}

	this.fetchFolderData();

	var sel = DOM.oils_rpt_folder_contents_action_selector;
	var x = true;
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];

		if( !mine && opt.getAttribute('value').match(/move/) ) {
			hideMe(opt);
			continue;
		}

		if( opt.getAttribute('type') == this.type ) {
			if(x && !opt.disabled) {
				opt.selected = true;
				x = false;
			}
			unHideMe(opt);
		} else hideMe(opt);
	}

	this.drawEditActions();

	var porg = PERMS.SHARE_REPORT_FOLDER;
	if( porg < 1 ) 
		DOM.oils_rpt_folder_manager_share_opt.disabled = true;
}

oilsRptFolderWindow.prototype.drawEditActions = function() {

	DOM.oils_rpt_folder_window_contents_new_template.onclick = function() {
		var s = location.search+'';
		s = s.replace(/\&folder=\d+/g,'');
		s = s.replace(/\&ct=\d+/g,'');
		goTo( OILS_TEMPLATE_INTERFACE+s+'&folder='+obj.folderNode.folder.id());
	}


	if( this.folderNode.folder.owner().id() != USER.id() )
		hideMe(DOM.oils_rpt_folder_manager_tab_table);
	else
		unHideMe(DOM.oils_rpt_folder_manager_tab_table);

	if( isTrue(this.folderNode.folder.shared())) {
		DOM.oils_rpt_folder_manager_share_opt.disabled = true;
		DOM.oils_rpt_folder_manager_unshare_opt.disabled = false;
	} else {
		DOM.oils_rpt_folder_manager_share_opt.disabled = false;
		DOM.oils_rpt_folder_manager_unshare_opt.disabled = true;
	}

	this.hideFolderActions();
	var obj = this;

	DOM.oils_rpt_folder_manager_actions_submit.onclick = function() {
		var act = getSelectorVal(DOM.oils_rpt_folder_manager_actions);
		_debug("doing folder action: " + act);
		obj.hideFolderActions();
		switch(act) {
			case 'change_name':
				unHideMe(DOM.oils_rpt_folder_manager_change_name_div);
				break;
			case 'create_sub_folder':
				var porg = PERMS.SHARE_REPORT_FOLDER;
				if( porg < 1 ) 
					DOM.oils_rpt_folder_manager_sub_shared.disabled = true;
				removeChildren(DOM.oils_rpt_folder_manager_sub_lib_picker);
				unHideMe(DOM.oils_rpt_folder_manager_create_sub);
				obj.myOrgSelector = new oilsRptMyOrgsWidget(
					DOM.oils_rpt_folder_manager_sub_lib_picker, USER.ws_ou(), porg)
				obj.myOrgSelector.draw();
				break;
			case 'delete':
				obj.doFolderDelete();
				break;
			case 'share':
				obj.shareFolder();
				break;
			case 'unshare':
				obj.unShareFolder();
				break;
		}
	}

}


oilsRptFolderWindow.prototype.shareFolder = function() {
	var folder = this.folderNode.folder;
	if(isTrue(folder.shared()))
		return alertId('oils_rpt_folder_already_shared');
	unHideMe(DOM.oils_rpt_folder_manager_share_div);


	var orgsel = new oilsRptMyOrgsWidget(
		DOM.oils_rpt_folder_manager_share_lib_picker, 
		USER.ws_ou(), PERMS.SHARE_REPORT_FOLDER);
	orgsel.draw();

	var type = this.type;
	DOM.oils_rpt_folder_manager_share_submit.onclick = function() {
		folder.shared('t');
		folder.share_with(orgsel.getValue());
		oilsRptUpdateFolder( folder, type, 
			function(success) {
				if(success) {
					oilsRptAlertSuccess();
					oilsRptCurrentFolderManager.draw();
				}
			}
		);
	}
}

oilsRptFolderWindow.prototype.unShareFolder = function() {
	var folder = this.folderNode.folder;
	if(!isTrue(folder.shared()))
		return alertId('oils_rpt_folder_already_unshared');
	if(!confirmId('oils_rpt_folder_unshare_confirm')) return;
	folder.shared('f');
	var type = this.type;
	oilsRptUpdateFolder( folder, type, 
		function(success) {
			if(success) {
				oilsRptAlertSuccess();
				oilsRptCurrentFolderManager.draw();
			}
		}
	);
}


oilsRptFolderWindow.prototype.hideFolderActions = function() {
	hideMe(DOM.oils_rpt_folder_manager_change_name_div);
	hideMe(DOM.oils_rpt_folder_manager_create_sub);
	hideMe(DOM.oils_rpt_folder_manager_share_div);
}


oilsRptFolderWindow.prototype.doFolderAction = function() {
	var objs = (this.fmTable) ? this.fmTable.getSelected() : [];

	if( this.type == 'output' && this.fmTable2 ) 
		objs = objs.concat( this.fmTable2.getSelected() );

	if( objs.length == 0 ) 
		return alert(rpt_strings.FOLDER_WINDOW_SELECT_ITEM);
	var action = getSelectorVal(DOM.oils_rpt_folder_contents_action_selector);

	var obj = this;
	var successCallback = function(errid) {
		if(errid) alertId(errid)
		else oilsRptAlertSuccess();
		obj.draw();
	};

	var obj = this;
	switch(action) {

		case 'create_report' :
			hideMe(DOM.oils_rpt_folder_table_right_td);
			unHideMe(DOM.oils_rpt_folder_table_alt_td);
			unHideMe(DOM.oils_rpt_editor_div);
			new oilsRptReportEditor(new oilsReport(objs[0]), this);
			break;
		case 'delete_report' :
			if(!confirmId('oils_rpt_verify_report_delete')) return;
			this.deleteReports(objs, 0, successCallback);
			break;

		case 'delete_template' :
            if(!confirmId('oils_rpt_verify_template_delete')) return;
			this.deleteTemplates(objs, 0, successCallback);
			break;

		case 'show_output':
			this.showOutput(objs[0]);
			break;

		case 'delete_output':
			if(!confirmId('oils_rpt_folder_contents_confirm_delete')) return;
			this.deleteOutputs(objs,0, successCallback);
			break;

		case 'move_template':
			this.changeBatchFolder(objs, 'template', successCallback);
			break;

		case 'move_report':
			this.changeBatchFolder(objs, 'report', successCallback);
			break;

		case 'move_output':
			this.changeBatchFolder(objs, 'output', successCallback);
			break;

		case 'clone_template':
			this.cloneTemplate(objs[0]);
	}
}

oilsRptFolderWindow.prototype.changeBatchFolder = function(objs, type, callback) {
	hideMe(DOM.oils_rpt_folder_window_contents_table);
	unHideMe(DOM.oils_rpt_move_folder_div)
	var obj = this;
	this.drawFolderOptions(type,	
		function(folderid) {
			obj.changeFolderList(objs, type, folderid, 0, callback);
			hideMe(DOM.oils_rpt_move_folder_div)
			unHideMe(DOM.oils_rpt_folder_window_contents_table);
		}
	);
}

oilsRptFolderWindow.prototype.cloneTemplate = function(template) {
	hideMe(DOM.oils_rpt_folder_window_contents_table);
	unHideMe(DOM.oils_rpt_move_folder_div)
	var obj = this;
	this.drawFolderOptions('template',
		function(folderid) {
			var s = location.search+'';
			s = s.replace(/\&folder=\d+/g,'');
			s = s.replace(/\&ct=\d+/g,'');
            version = JSON2js(template.data()).version;
            if(version && version >= 2) {
                _debug('entering new template building interface with template version ' + version);
			    goTo(OILS_TEMPLATE_INTERFACE+s+'&folder='+folderid+'&ct='+template.id());
            } else {
			    goTo(OILS_LEGACY_TEMPLATE_INTERFACE+s+'&folder='+folderid+'&ct='+template.id());
            }
		}
	);
}


oilsRptFolderWindow.prototype.changeFolderList = function(list, type, folderid, idx, callback, errid) {
	if( idx >= list.length ) return callback(errid);
	var item = list[idx];
	var obj	= this;
	var rcback = function(){obj.changeFolderList(list,type,folderid,++idx,callback,errid)};

	item.folder(folderid);

	switch(type) {
		case 'template':
			oilsRptUpdateTemplate(item,rcback);
			break;
		case 'report':
			oilsRptUpdateReport(item,rcback);
			break;
		case 'output':
			oilsRptUpdateSchedule(item,rcback);
			break;
	}
}

oilsRptFolderWindow.prototype.drawFolderOptions = function(type, callback) {
	//var oilsRptChangeFolderTree;
	var selectedFolder;
	oilsRptBuildFolder(
		type,
		DOM.oils_rpt_move_folder_picker,
		'tree9807897',
		rpt_strings.FOLDER_WINDOW_CHANGE_FOLDERS,
		function(node) { 
			appendClear(DOM.oils_rpt_move_folder_selected, node.folder.name());
			selectedFolder = node.folder.id();
		} 
	);

	DOM.oils_rpt_change_folder_submit.onclick = function() {
		if(selectedFolder) callback(selectedFolder);
	}

	DOM.oils_rpt_change_folder_cancel.onclick = function() {
		hideMe(DOM.oils_rpt_move_folder_div)
		unHideMe(DOM.oils_rpt_folder_window_contents_table);
	}
}


oilsRptFolderWindow.prototype.deleteOutputs = function(list, idx, callback, errid) {
	if( idx >= list.length ) return callback(errid);
	var output = list[idx];

	if( output.runner().id()  != USER.id() ) {
		this.deleteOutputs(list, ++idx, 
			callback, 'oils_rpt_folder_contents_no_delete');

	} else {
		_debug('deleting output ' + output.id());
		var req = new Request(OILS_RPT_DELETE_SCHEDULE,SESSION,output.id());
		var obj = this;
		req.callback(function(){obj.deleteOutputs(list, ++idx, callback, errid);});
		req.send();
	}
}

oilsRptFolderWindow.prototype.showOutput = function(sched) {
	oilsRptFetchReport(sched.report().id(), 
		function(r) {
			var url = oilsRptBuildOutputLink(r.template(), r.id(), sched.id());
			_debug("launching report output view at URL: " + url);
			if(isXUL()) 
				xulG.new_tab(xulG.url_prefix('XUL_REMOTE_BROWSER?url=') + url,
					{tab_name: dojo.string.substitute( rpt_strings.FOLDER_WINDOW_REPORT_OUTPUT, [r.name()] ), browser:false},
					{no_xulG:false, show_nav_buttons:true, show_print_button:true});
			else {
				//goTo(url);
				var win = window.open(url,r.name(), 'resizable,width=800,height=600,scrollbars=1'); 
			}
		}
	);
}


oilsRptFolderWindow.prototype.deleteReports = function(list, idx, callback, errid) {
	if( idx >= list.length ) return callback(errid);
	var report = list[idx];

	var obj = this;
	if( report.owner().id() != USER.id() ) {
		this.deleteReports(list, ++idx, 
			callback, 'oils_rpt_folder_contents_no_delete');

	} else {

//		var req0 = new Request(OILS_RPT_REPORT_HAS_OUTS, SESSION, report.id());
//		req0.callback(
//			function(r0) {
//				var r0es = r0.getResultObject();
//				if( r0es != '0' ) {
//					obj.deleteReports(list, ++idx, 
//						callback, 'oils_rpt_folder_contents_report_no_delete');
//				} else {
					_debug('deleting report ' + report.id());
					var req = new Request(OILS_RPT_DELETE_REPORT, SESSION, report.id());
					req.callback(function(r) { 
						var res = r.getResultObject();
						if( res == 0 ) return oilsRptAlertFailure();
						obj.deleteReports(list, ++idx, callback, errid)
					});
					req.send();
//				}
//			}
//		);
//
//		req0.send();
	}
}

oilsRptFolderWindow.prototype.deleteTemplates = function(list, idx, callback, errid) {
	if( idx >= list.length ) return callback(errid);
	var tmpl = list[idx];

	var obj = this;
	if( tmpl.owner().id() != USER.id() ) {
		this.deleteTemplates(list, ++idx, 
			callback, 'oils_rpt_folder_contents_no_delete');

	} else {


//		var req0 = new Request(	OILS_RPT_TEMPLATE_HAS_RPTS, SESSION, tmpl.id() );
//		req0.callback(
//			function(r0) {
//				var resp = r0.getResultObject();
//
//				if( resp != '0' ) {
//					obj.deleteTemplates(list, ++idx, 
//						callback, 'oils_rpt_folder_contents_template_no_delete');
//
//				} else {
					_debug('deleting template ' + tmpl.id());
					var req = new Request(OILS_RPT_DELETE_TEMPLATE, SESSION, tmpl.id());
					req.callback(function(r) {
						var res = r.getResultObject();
						if( res == 0 ) return oilsRptAlertFailure();
						obj.deleteTemplates(list, ++idx, callback, errid)
					});
					req.send();
//				}
//			}
//		);
//		req0.send();
	}
}



oilsRptFolderWindow.prototype.drawFolderDetails = function() {
	appendClear(DOM.oils_rpt_folder_creator_label, 
		text(this.folderNode.folder.owner().usrname()));
	appendClear(DOM.oils_rpt_folder_name_label, 
		text(this.folderNode.folder.name()));
}


oilsRptFolderWindow.prototype.fetchFolderData = function(callback) {

	hideMe(DOM.oils_rpt_content_count_row_2);
	hideMe(DOM.oils_rpt_content_row_2);

	removeChildren(this.selector);
	var req = new Request(OILS_RPT_FETCH_FOLDER_DATA, 
		SESSION, this.type, this.folderNode.folder.id(), oilsRptOutputLimit);

	hideMe(DOM.oils_rpt_pending_output);

	if(this.type == 'output') {
		unHideMe(DOM.oils_rpt_pending_output);
		/* first fetch the non-complete schedules */
		req = new Request(OILS_RPT_FETCH_OUTPUT, 
			SESSION, this.folderNode.folder.id(), oilsRptOutputLimit, 0);
	}

	var obj = this;
	removeChildren(obj.selector);
	req.callback(
		function(r) {
			var res = r.getResultObject();

			if( res.length == 0 ) {
				//hideMe(DOM.oils_rpt_content_count_row); /* this also hides the new-template link.. fix me */
				hideMe(DOM.oils_rpt_content_row);
				unHideMe(DOM.oils_rpt_content_row_empty);
			} else {
				unHideMe(DOM.oils_rpt_content_count_row);
				unHideMe(DOM.oils_rpt_content_row);
				hideMe(DOM.oils_rpt_content_row_empty);
			}

			if( obj.type == 'output' ) {
				obj.fleshSchedules(res, 0, obj.selector);
			} else {


				obj.fmTable = drawFMObjectTable( 
					{ 
						dest : obj.selector, 
						obj : res,
						selectCol : true,
						selectColName : rpt_strings.FOLDER_WINDOW_COLNAME_SELECT,
						selectAllName : rpt_strings.FOLDER_WINDOW_COLNAME_ALL,
						selectNoneName : rpt_strings.FOLDER_WINDOW_COLNAME_NONE
					}
				);
			}
		}
	);
	req.send();

	if( this.type != 'output' ) return;

	/*
	unHideMe(DOM.oils_rpt_content_count_row_2);
	unHideMe(DOM.oils_rpt_content_row_2);
	*/

	/* now fetch the completed schedules */
	req = new Request(OILS_RPT_FETCH_OUTPUT, 
		SESSION, this.folderNode.folder.id(), oilsRptOutputLimit2, 1);

	_debug("TRYING: fleshing finished scheds with div: " + DOM.oils_rpt_folder_contents_selector_2);
	removeChildren(DOM.oils_rpt_folder_contents_selector_2);
	req.callback(
		function(r) {
			var res = r.getResultObject();

			if( res.length == 0 ) {
				hideMe(DOM.oils_rpt_content_count_row_2);
				hideMe(DOM.oils_rpt_content_row_2);
			} else {
				unHideMe(DOM.oils_rpt_content_count_row_2);
				unHideMe(DOM.oils_rpt_content_row_2);
			}

			_debug("fleshing finished scheds with div: " + DOM.oils_rpt_folder_contents_selector_2);
			obj.fleshSchedules(res, 0, DOM.oils_rpt_folder_contents_selector_2, true);
		}
	);
	req.send();
}


oilsRptFolderWindow.prototype.fleshSchedules = function(list, idx, selector, isSecond) {

	if( idx >= list.length ) return;

	var sched = list[idx];
	var obj = this;

	oilsRptFetchUser(sched.runner(),

		function(user) {
			sched.runner(user);
			oilsRptFetchTemplate(sched.report().template(),

				function(template) {
					sched.report().template(template);
					if( idx == 0 ) {
						_debug("drawing schedule with output: "+selector);
						var t = drawFMObjectTable( 
							{ 
								dest : selector, 
								obj : [sched],
								selectCol : true,
								selectColName : rpt_strings.FOLDER_WINDOW_COLNAME_SELECT,
								selectAllName : rpt_strings.FOLDER_WINDOW_COLNAME_ALL,
								selectNoneName : rpt_strings.FOLDER_WINDOW_COLNAME_NONE
							}
						);

						if( isSecond ) obj.fmTable2 = t;
						else obj.fmTable = t;

					} else {
						//obj.fmTable.add(sched);
						if( isSecond ) obj.fmTable2.add(sched);
						else obj.fmTable.add(sched);
					}

					obj.fleshSchedules(list, ++idx, selector, isSecond);
				}
			);
		}
	);
}


oilsRptFolderWindow.prototype.setSelected = function(folderNode) {
	this.selectedFolder = folderNode;
}

oilsRptFolderWindow.prototype.setFolderEditActions = function() {
	var folder = this.folderNode.folder;

	var obj = this;
	DOM.oils_rpt_folder_manager_name_input.value = folder.name();
	DOM.oils_rpt_folder_manager_change_name_submit.onclick = function() {
		var name = DOM.oils_rpt_folder_manager_name_input.value;
		if(name != "") {
			folder.name( name );
			if(confirmId('oils_rpt_folder_manager_change_name_confirm')) {
				oilsRptUpdateFolder(folder, obj.type,
					function(success) {
						if(success) {
							oilsRptAlertSuccess();
							oilsRptCurrentFolderManager.draw();
						}
					}
				);
			}
		}
	}

	DOM.oils_rpt_folder_manager_sub_lib_create.onclick = function() {
		var folder;

		if( obj.type == 'report' ) folder = new rrf();
		if( obj.type == 'template' ) folder = new rtf();
		if( obj.type == 'output' ) folder = new rof();

		folder.owner(USER.id());
		folder.parent(obj.folderNode.folder.id());
		folder.name(DOM.oils_rpt_folder_manager_sub_name.value);
		var shared = getSelectorVal(DOM.oils_rpt_folder_manager_sub_shared);
		folder.shared( (shared == 'yes') ? 't' : 'f');
		if( folder.shared() == 't' )
			folder.share_with( obj.myOrgSelector.getValue() );

		oilsRptCreateFolder(folder, obj.type,
			function(success) {
				if(success) {
					oilsRptAlertSuccess();
					oilsRptCurrentFolderManager.draw();
				}
			}
		);
	}
}


oilsRptFolderWindow.prototype.doFolderDelete = function() {
	
	var cache = oilsRptFolderNodeCache[this.type];
	/* let's see if this folder has any children */
	for( var c in cache ) 
		if( cache[c].folder.parent() == this.folderNode.folder.id() )
			return alertId('oils_rpt_folder_cannot_delete');

	/* lets see if the folder has contents */
	var req = new Request(OILS_RPT_FETCH_FOLDER_DATA, 
		SESSION, this.type, this.folderNode.folder.id(), 1);

	if(this.type == 'output') {
		req = new Request(OILS_RPT_FETCH_OUTPUT, 
			SESSION, this.folderNode.folder.id(), 1);
	}

	var obj = this;
	req.send();

	req.callback( 
		function(r) {

			var contents = r.getResultObject();
			if( contents.length > 0 ) 
				return alertId('oils_rpt_folder_cannot_delete');

			if( confirmId('oils_rpt_folder_manager_delete_confirm') ) {
				var req2 = new Request(OILS_RPT_DELETE_FOLDER, 
					SESSION, obj.type, obj.folderNode.folder.id());
	
				req2.callback( 
					function(r2) {
						var res = r2.getResultObject();
						if( res == 1 ) {
							oilsRptAlertSuccess();
							oilsRptCurrentFolderManager.draw();
						}
						else alert('error: '+js2JSON(res));
					}
				);

				req2.send();
			}
		}
	);
}


