dump('entering admin/offline_manage_xacts.js\n');

if (typeof admin == 'undefined') admin = {};
admin.offline_manage_xacts = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
}

admin.offline_manage_xacts.prototype = {

	'sel_list' : [],

	'init' : function( params ) {

		var obj = this;

		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

		JSAN.use('util.list'); obj.list = new util.list('session_tree');
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
					'label' : 'Uploads Processed', 
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
				JSAN.use('util.functional');
				var sel = obj.list.retrieve_selection();
				obj.sel_list = util.functional.map_list(
					sel,
					function(o) { return o.getAttribute('retrieve_id'); }
				);
				if (obj.check_perm(obj.session,'OFFLINE_EXECUTE_SESSION')) {
					document.getElementById('execute').disabled = false;	
				}
				if (obj.check_perm(obj.session,'OFFLINE_UPLOAD_XACTS')) {
					document.getElementById('upload').disabled = false;	
				}
				if (obj.check_perm(obj.session,'OFFLINE_SESSION_ERRORS')) {
					document.getElementById('errors').disabled = false;	
				}
				obj.render_scriptlist();
			},
		} );

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


		obj.retrieve_seslist();
		obj.render_seslist();

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

		x = document.getElementById('errors');
		x.addEventListener('command',function() { try{obj.ses_errors();}catch(E){alert(E);} },false);
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
				+ "&seskey=" + window.escape(obj.sel_list[i])
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

		for (var i = 0; i < obj.sel_list.length; i++) {

			var url  = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI)
				+ "?ses=" + window.escape(obj.data.session)
				+ "&action=status" 
				+ "&seskey=" + window.escape(obj.sel_list[i])
				+ "&ws=" + window.escape(obj.data.ws_name)
				+ '&status_type=exceptions';
			var x = new XMLHttpRequest();
			x.open("GET",url,false);
			x.send(null);

			dump(url + ' = ' + x.responseText + '\n' );
			var robj = JSON2js(x.responseText);

			alert(js2JSON(robj));

		}
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
		var seskey = obj.sel_list[0];
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
			+ "&seskey=" + window.escape(obj.sel_list[0])
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
				function(row){ 
					return function(){
						obj.list.append( { 'retrieve_id' : row.key, 'row' : row } );
					};
				}(obj.seslist[i]) 
			);
		}
		JSAN.use('util.exec'); var exec = new util.exec();
		exec.chain( funcs );

		document.getElementById('execute').disabled = true;
		document.getElementById('errors').disabled = true;
		document.getElementById('upload').disabled = true;

	},

	'render_scriptlist' : function() {

		var obj = this;

		obj.script_list.clear();

		var scripts = obj.ses_status().scripts;

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
}

dump('exiting admin/offline_manage_xacts.js\n');
