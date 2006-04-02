dump('entering admin/offline_manage_xacts.js\n');

if (typeof admin == 'undefined') admin = {};
admin.offline_manage_xacts = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
}

admin.offline_manage_xacts.prototype = {

	'sel_list' : [],
	'seslist' : [],

	'init' : function( params ) {

		var obj = this;

		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

		obj.init_list(); obj.init_script_list(); obj.init_error_list();

		obj.retrieve_seslist(); obj.render_seslist();

		var x = document.getElementById('create');
		if (obj.check_perm(obj.session,'OFFLINE_CREATE_SESSION')) {
			x.disabled = false;
			x.addEventListener('command',function() { try{obj.create_ses();}catch(E){alert(E);} },false);
		}

		x = document.getElementById('upload');
		x.addEventListener('command',function() { try{obj.upload();}catch(E){alert(E);} },false);

		x = document.getElementById('refresh');
		x.addEventListener('command',function() { try{obj.retrieve_seslist();obj.render_seslist();}catch(E){alert(E);} },false);

		x = document.getElementById('execute');
		x.addEventListener('command',function() { try{obj.execute_ses();}catch(E){alert(E);} },false);

		document.getElementById('deck').selectedIndex = 2;
	},

	'init_list' : function() {
		var obj = this; JSAN.use('util.list'); 
		obj.list = new util.list('session_tree');
		obj.list.init( {
			'columns' : [
				{
					'id' : 'org', 'hidden' : 'true', 'flex' : '1',
					'label' : 'Organization',
					'render' : 'data.hash.aou[ my.org ].shortname()',
				},
				{ 
					'id' : 'description', 'flex' : '2',
					'label' : 'Description', 
					'render' : "my.description", 
				},
				{
					'id' : 'create_time', 'flex' : '1',
					'label' : 'Date Created',
					'render' : 'if (my.create_time) { var x = new Date(); x.setTime(my.create_time+"000"); util.date.formatted_date(x,"%F %H:%M"); } else { ""; }',
				},
				{
					'id' : 'creator', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Created By',
					'render' : 'my.creator',
				},
				{ 
					'id' : 'count', 'flex' : '1',
					'label' : 'Upload Count', 
					'render' : "my.scripts.length", 
				},
				{ 
					'id' : 'num_complete', 'flex' : '1', 
					'label' : 'Transactions Processed', 
					'render' : "my.num_complete", 
				},
				{ 
					'id' : 'in_process', 'flex' : '1',
					'label' : 'Processing?', 
					'render' : "if (my.end_time) { 'Completed' } else {my.in_process == 0 ? 'No' : 'Yes'}", 
				},
				{
					'id' : 'start_time', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Date Started',
					'render' : 'if (my.start_time) {var x = new Date(); x.setTime(my.start_time+"000"); util.date.formatted_date(x,"%F %H:%M");} else { ""; }',
				},
				{
					'id' : 'end_time', 'flex' : '1',
					'label' : 'Date Completed',
					'render' : 'if (my.end_time) {var x = new Date(); x.setTime(my.end_time+"000"); util.date.formatted_date(x,"%F %H:%M");} else { ""; }',
				},
				{ 
					'id' : 'key', 'hidden' : 'true', 'flex' : '1', 
					'label' : 'Session', 
					'render' : "my.key", 
				},
			],
			'map_row_to_column' : function(row,col) {
				JSAN.use('util.date');
				JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
				var my = row; var value;
				try { value = eval( col.render ); } catch(E) { obj.error.sdump('D_ERROR',E); value = '???'; }
				return value;
			},
			'on_select' : function(ev) {
				try {
					JSAN.use('util.functional');
					var sel = obj.list.retrieve_selection();
					obj.sel_list = util.functional.map_list(
						sel,
						function(o) { return o.getAttribute('retrieve_id'); }
					);
					if (obj.sel_list.length == 0) return;
					if (obj.check_perm(obj.session,'OFFLINE_EXECUTE_SESSION')) {
						document.getElementById('execute').disabled = false;	
					}
					if (obj.check_perm(obj.session,'OFFLINE_UPLOAD_XACTS')) {
						document.getElementById('upload').disabled = false;	
					}
					var complete = false;
					for (var i = 0; i < obj.sel_list.length; i++) { 
						if (obj.seslist[ obj.sel_list[i] ].end_time) { complete = true; }
					}
					if (complete) {
						obj.render_errorlist();
					} else {
						obj.render_scriptlist();
					}
				} catch(E) {
					alert('on_select:\nobj.seslist.length = ' + obj.seslist.length + '  obj.sel_list.length = ' + obj.sel_list.length + '\nerror: ' + E);
				}
			},
		} );


	},

	'init_script_list' : function() {
		var obj = this; JSAN.use('util.list'); 
		obj.script_list = new util.list('script_tree');
		obj.script_list.init( {
			'columns' : [
				{
					'id' : 'create_time', 'flex' : '1',
					'label' : 'Date Uploaded',
					'render' : 'if (my.create_time) { var x = new Date(); x.setTime(my.create_time+"000"); util.date.formatted_date(x,"%F %H:%M"); } else { ""; }',
				},
				{
					'id' : 'requestor', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Uploaded By',
					'render' : 'my.requestor',
				},
				{ 
					'id' : 'time_delta', 'hidden' : 'true', 'flex' : '1', 
					'label' : 'Server/Local Time Delta', 
					'render' : "my.time_delta", 
				},
				{ 
					'id' : 'workstation', 'flex' : '1', 
					'label' : 'Workstation', 
					'render' : "my.workstation", 
				},
			],
			'map_row_to_column' : function(row,col) {
				JSAN.use('util.date');
				JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
				var my = row; var value;
				try { value = eval( col.render ); } catch(E) { obj.error.sdump('D_ERROR',E); value = '???'; }
				return value;
			},
		} );


	},

	'init_error_list' : function() {
		var obj = this; JSAN.use('util.list'); 
		obj.error_list = new util.list('error_tree');
		obj.error_list.init( {
			'columns' : [
				{
					'id' : 'workstation', 'flex' : '1',
					'label' : 'Workstation',
					'render' : 'my.command._workstation ? my.command._workstation : my.command._worksation',
				},
				{
					'id' : 'timestamp', 'flex' : '1',
					'label' : 'Timestamp',
					'render' : 'if (my.command.timestamp) { var x = new Date(); x.setTime(my.command.timestamp+"000"); util.date.formatted_date(x,"%F %H:%M"); } else { my.command._realtime; }',
				},
				{
					'id' : 'type', 'flex' : '1',
					'label' : 'Type',
					'render' : 'my.command.type',
				},
				{ 
					'id' : 'ilsevent', 'hidden' : 'true', 'flex' : '1', 
					'label' : 'Event Code', 
					'render' : "my.event.ilsevent", 
				},
				{ 
					'id' : 'textcode', 'flex' : '1', 
					'label' : 'Event Name', 
					'render' : "my.event.textcode", 
				},
				{
					'id' : 'i_barcode', 'flex' : '1',
					'label' : 'Item Barcode',
					'render' : 'my.command.barcode ? my.command.barcode : ""',
				},
				{
					'id' : 'p_barcode', 'flex' : '1',
					'label' : 'Patron Barcode',
					'render' : 'if (my.command.patron_barcode) { my.command.patron_barcode; } else { if (my.command.user.card.barcode) { my.command.user.card.barcode; } else { ""; } }',
				},
				{
					'id' : 'duedate', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Due Date',
					'render' : 'my.command.due_date || ""',
				},
				{
					'id' : 'backdate', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Check In Backdate',
					'render' : 'my.command.backdate || ""',
				},
				{
					'id' : 'count', 'flex' : '1', 'hidden' : 'true',
					'label' : 'In House Use Count',
					'render' : 'my.command.count || ""',
				},
				{
					'id' : 'noncat', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Non-Cataloged?',
					'render' : 'my.command.noncat == 1 ? "Yes" : "No"',
				},
				{
					'id' : 'noncat_type', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Non-Cataloged Type',
					'render' : 'data.hash.cnct[ my.command.noncat_type ] ? data.hash.cnct[ my.command.noncat_type ].name() : ""',
				},
				{
					'id' : 'noncat_count', 'flex' : '1', 'hidden' : 'true',
					'label' : 'Non-Cataloged Count',
					'render' : 'my.command.noncat_count || ""',
				},
			],
			'map_row_to_column' : function(row,col) {
				JSAN.use('util.date');
				JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
				var my = row; var value;
				try { value = eval( col.render ); } catch(E) { obj.error.sdump('D_ERROR',E); value = '???'; }
				return value;
			},
		} );


	},

	'check_perm' : function(ses,perms) {
		return true; /* FIXME */
	},

	'execute_ses' : function() {
		var obj = this;

		obj.data.stash_retrieve();

		for (var i = 0; i < obj.sel_list.length; i++) {

			var url  = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI)
				+ "?ses=" + window.escape(obj.data.session)
				+ "&action=execute" 
				+ "&seskey=" + window.escape(obj.seslist[obj.sel_list[i]].key)
				+ "&ws=" + window.escape(obj.data.ws_name);
			var x = new XMLHttpRequest();
			x.open("GET",url,false);
			x.send(null);

			dump(url + ' = ' + x.responseText + '\n' );
			var robj = JSON2js(x.responseText);

			if (robj.ilsevent != 0) { alert('Execute error: ' + x.responseText); }

			obj.retrieve_seslist(); obj.render_seslist();
		}
	},

	'ses_errors' : function() {
		var obj = this;

		obj.data.stash_retrieve();

		var url  = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI)
			+ "?ses=" + window.escape(obj.data.session)
			+ "&action=status" 
			+ "&seskey=" + window.escape(obj.seslist[ obj.sel_list[0] ].key)
			+ "&ws=" + window.escape(obj.data.ws_name)
			+ '&status_type=exceptions';
		var x = new XMLHttpRequest();
		x.open("GET",url,false);
		x.send(null);

		dump(url + ' = ' + x.responseText + '\n' );
		var robj = JSON2js(x.responseText);

		return { 'errors' : robj, 'description' : obj.seslist[ obj.sel_list[0] ].description };

	},

	'rename_file' : function() {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		var obj = this;
		JSAN.use('util.file'); 
		var pending = new util.file('pending_xacts');
		if ( !pending._file.exists() ) { throw("Can't rename a non-existent file"); }
		obj.transition_filename = 'pending_xacts_' + new Date().getTime();
		var count = 0;
		var file = new util.file(obj.transition_filename);
		while (file._file.exists()) {
			obj.transition_filename = 'pending_xacts_' + new Date().getTime();
			file = new util.file(obj.transition_filename);
			if (count++>100) throw("Taking too long to find a unique filename.");
		}
		pending._file.moveTo(null,obj.transition_filename);
	},

	'revert_file' : function() {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		var obj = this;
		JSAN.use('util.file');
		var pending = new util.file('pending_xacts');
		if (pending._file.exists()) { alert('Something bad happened.  New offline transactions were accumulated during our attempted upload.  Tell your system admin that the file involved is ' + obj.transition_filename); return; }
		var file = new util.file(obj.transition_filename);
		file._file.moveTo(null,'pending_xacts');
	},

	'archive_file' : function() {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		var obj = this;
		JSAN.use('util.file');
		var file = new util.file(obj.transition_filename);
		if (file._file.exists()) file._file.moveTo(null,obj.transition_filename + '.complete')
	},

	'upload' : function() {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		var obj = this;
		if (obj.sel_list.length == 0) { alert('Please select a session to upload to.'); return; }
		if (obj.sel_list.length > 1) { alert('Please select a single session to upload to.'); return; }

		JSAN.use('util.file');

		var file = new util.file('pending_xacts');
		if (!file._file.exists()) { alert('No pending transactions to upload.'); return; }

		obj.rename_file();

		obj.data.stash_retrieve();
		var seskey = obj.seslist[ obj.sel_list[0] ].key;
		JSAN.use('util.widgets');
		var xx = document.getElementById('iframe_placeholder'); util.widgets.remove_children(xx);
		var x = document.createElement('iframe'); xx.appendChild(x); x.flex = 1;
		x.setAttribute(
			'src',
			window.xulG.url_prefix( urls.XUL_REMOTE_BROWSER )
			+ '?url=' + window.escape(
				urls.XUL_OFFLINE_UPLOAD_XACTS
				+ '?ses=' + window.escape(obj.data.session)
				+ '&seskey=' + window.escape(seskey)
				+ '&ws=' + window.escape(obj.data.ws_name)
				+ '&delta=' + window.escape('0')
				+ '&filename=' + window.escape( obj.transition_filename )
			)
		);
		var newG = { 
			'url_prefix' : window.xulG.url_prefix, 
			'passthru_content_params' : {
				'url_prefix' : window.xulG.url_prefix,
				'handle_event' : function(robj){
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					try {
						dump('robj = ' + js2JSON(robj) + '\n');
						if ( robj.ilsevent != 0 ) {
							obj.revert_file();
							alert('There was an error:\n' + js2JSON(robj));
						} else {
							obj.archive_file();
						}
						obj.retrieve_seslist(); obj.render_seslist();
						setTimeout(
							function() {
								JSAN.use('util.widgets');
								util.widgets.remove_children('iframe_placeholder');
							},0
						);
					} catch(E) {
						alert('handle_event error: ' + E);
					}
				} 
			}
		};
		x.contentWindow.xulG = newG;
	},

	'ses_status' : function() {
		var obj = this;

		obj.data.stash_retrieve();

		var url  = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI)
			+ "?ses=" + window.escape(obj.data.session)
			+ "&action=status" 
			+ "&seskey=" + window.escape(obj.seslist[obj.sel_list[0]].key)
			+ "&ws=" + window.escape(obj.data.ws_name)
			+ "&status_type=scripts";
		var x = new XMLHttpRequest();
		x.open("GET",url,false);
		x.send(null);

		dump(url + ' = ' + x.responseText + '\n' );
		var robj = JSON2js(x.responseText);

		return robj;
	},

	'create_ses' : function() {

		var obj = this;

		var desc = window.prompt('Please enter a description:','','Create an Offline Transaction Session');
		if (desc=='' || desc==null) { return; }

		obj.data.stash_retrieve();

		var url  = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI)
			+ "?ses=" + window.escape(obj.data.session)
			+ "&action=create" 
			+ "&desc=" + window.escape(desc)
			+ "&ws=" + window.escape(obj.data.ws_name);
		var x = new XMLHttpRequest();
		x.open("GET",url,false);
		x.send(null);

		dump(url + ' = ' + x.responseText + '\n' );
		var robj = JSON2js(x.responseText);
		if (robj.ilsevent == 0) {
			obj.retrieve_seslist(); obj.render_seslist();
		} else {
			alert('Error: ' + x.responseText);
		}
	},

	'retrieve_seslist' : function() {

		var obj = this;

		obj.data.stash_retrieve();

		var url = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI) 
			+ "?ses=" + window.escape(obj.data.session)
			+ "&action=status"
			+ "&org=" + window.escape(obj.data.list.au[0].ws_ou())
			+ "&status_type=sessions";
		var x = new XMLHttpRequest();
		x.open("GET",url,false);
		x.send(null);

		dump(url + ' = ' + x.responseText + '\n' );
		obj.seslist = JSON2js( x.responseText );
	},

	'render_seslist' : function() {

		var obj = this;

		obj.list.clear();

		var funcs = [];
		for (var i = 0; i < obj.seslist.length; i++) {
			funcs.push( 
				function(idx,row){ 
					return function(){
						obj.list.append( { 'retrieve_id' : idx, 'row' : row } );
					};
				}(i,obj.seslist[i]) 
			);
		}
		JSAN.use('util.exec'); var exec = new util.exec();
		exec.chain( funcs );

		document.getElementById('execute').disabled = true;
		document.getElementById('upload').disabled = true;

	},

	'render_scriptlist' : function() {

		dump('render_scriptlist\n');

		document.getElementById('deck').selectedIndex = 0;

		var obj = this;

		obj.script_list.clear();

		var status = obj.ses_status();
		document.getElementById('status_caption').setAttribute('label','Uploaded Transactions for ' + status.description);

		var scripts = status.scripts;

		var funcs = [];
		for (var i = 0; i < scripts.length; i++) {
			funcs.push( 
				function(row){ 
					return function(){
						obj.script_list.append( { 'row' : row } );
					};
				}(scripts[i]) 
			);
		}
		JSAN.use('util.exec'); var exec = new util.exec();
		exec.chain( funcs );
	},
	
	'render_errorlist' : function() {

		dump('render_errorlist\n');

		document.getElementById('deck').selectedIndex = 1;

		var obj = this;

		obj.error_list.clear();

		var error_meta = obj.ses_errors();
		document.getElementById('errors_caption').setAttribute('label','Exceptions for ' + error_meta.description);

		obj.errors = error_meta.errors;

		var funcs = [];
		for (var i = 0; i < obj.errors.length; i++) {
			funcs.push( 
				function(idx,row){ 
					return function(){
						obj.error_list.append( { 'retrieve_id' : idx, 'row' : row } );
					};
				}(i,obj.errors[i]) 
			);
		}
		JSAN.use('util.exec'); var exec = new util.exec();
		exec.chain( funcs );
	},

}

dump('exiting admin/offline_manage_xacts.js\n');
