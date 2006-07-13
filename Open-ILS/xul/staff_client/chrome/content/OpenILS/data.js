dump('entering OpenILS/data.js\n');

if (typeof OpenILS == 'undefined') OpenILS = {};
OpenILS.data = function () {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();

	return this;
}

OpenILS.data.prototype = {

	'list' : {},
	'hash' : {},
	'tree' : {},

	'temp' : '',

	'init' : function (params) {

		try {
			if (params && params.via == 'stash') {	
				this.stash_retrieve();
			} else {
				this.network_retrieve();
			}
		
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data.init('
				+js2JSON(params)+'): ' + js2JSON(E) );
		}


	},

	'stash' : function () {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			var data_cache=new OpenILS( );
			for (var i = 0; i < arguments.length; i++) {
				try {
					if (arguments[i] != 'hash' && arguments[i] != 'list') this.error.sdump('D_DATA_STASH','stashing ' + arguments[i] + ' : ' + this[arguments[i]] + (typeof this[arguments[i]] == 'object' ? ' = ' + js2JSON(this[arguments[i]]) : '') + '\n');
				} catch(F) { alert(F); }
				data_cache.wrappedJSObject.OpenILS.prototype.data[arguments[i]] = this[arguments[i]];
			}
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data.stash(): ' + js2JSON(E) );
		}
	},

	'_debug_stash' : function() {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			var data_cache=new OpenILS( );
			for (var i in data_cache.wrappedJSObject.OpenILS.prototype.data) {
				dump('_debug_stash ' + i + '\n');
			}
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data._debug_stash(): ' + js2JSON(E) );
		}
	},

	'_fm_objects' : {

		'pgt' : [ api.FM_PGT_RETRIEVE.app, api.FM_PGT_RETRIEVE.method, [], true ],
		'cit' : [ api.FM_CIT_RETRIEVE.app, api.FM_CIT_RETRIEVE.method, [], true ],
		'citm' : [ api.FM_CITM_RETRIEVE.app, api.FM_CITM_RETRIEVE.method, [], true ],
		/*
		'cst' : [ api.FM_CST_RETRIEVE.app, api.FM_CST_RETRIEVE.method, [], true ],
		*/
		'acpl' : [ api.FM_ACPL_RETRIEVE.app, api.FM_ACPL_RETRIEVE.method, [], true ],
		'ccs' : [ api.FM_CCS_RETRIEVE.app, api.FM_CCS_RETRIEVE.method, [], true ],
		'aou' : [ api.FM_AOU_RETRIEVE.app, api.FM_AOU_RETRIEVE.method, [], true ],
		'aout' : [ api.FM_AOUT_RETRIEVE.app, api.FM_AOUT_RETRIEVE.method, [], true ],
		'crahp' : [ api.FM_CRAHP_RETRIEVE.app, api.FM_CRAHP_RETRIEVE.method, [], true ],
	},

	'stash_retrieve' : function() {
		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			const OpenILS=new Components.Constructor("@mozilla.org/openils_data_cache;1", "nsIOpenILS");
			var data_cache=new OpenILS( );
			var dc = data_cache.wrappedJSObject.OpenILS.prototype.data;
			for (var i in dc) {
				this.error.sdump('D_DATA_RETRIEVE','Retrieving ' + i + ' : ' + dc[i] + '\n');
				this[i] = dc[i];
			}
			if (typeof this.on_complete == 'function') {

				this.on_complete();
			}
		} catch(E) {
			this.error.sdump('D_ERROR','Error in OpenILS.data._debug_stash(): ' + js2JSON(E) );
		}
	},

	'print_list_defaults' : function() {
		var obj = this;
		//if (typeof obj.print_list_templates == 'undefined') {
		{
			obj.print_list_types = [ 
				'offline_checkout', 
				'offline_checkin', 
				'offline_renew', 
				'offline_inhouse_use', 
				'items', 
				'bills', 
				'payment', 
				'holds', 
				/* 'patrons' */
			];
			obj.print_list_templates = { 
				'item_status' : {
					'type' : 'items',
					'header' : 'The following items have been examined:<hr/><ol>',
					'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode%\r\n',
					'footer' : '</ol><hr />%PINES_CODE% %TODAY_TRIM%<br/>\r\n<br/>\r\n',
				}, 
				'items_out' : {
					'type' : 'items',
					'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!<br/>\r\nYou have the following items:<hr/><ol>',
					'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode% Due: %due_date%\r\n',
					'footer' : '</ol><hr />%PINES_CODE% %TODAY_TRIM%<br/>\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%<br/>\r\n<br/>\r\n',
				}, 
				'checkout' : {
					'type' : 'items',
					'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!<br/>\r\nYou checked out the following items:<hr/><ol>',
					'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode% Due: %due_date%\r\n',
					'footer' : '</ol><hr />%PINES_CODE% %TODAY_TRIM%<br/>\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%<br/>\r\n<br/>\r\n',
				}, 
				'offline_checkout' : {
					'type' : 'offline_checkout',
					'header' : 'Patron %patron_barcode%<br/>\r\nYou checked out the following items:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%<br/>\r\nDue: %due_date%\r\n',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
				'checkin' : {
					'type' : 'items',
					'header' : 'You checked in the following items:<hr/><ol>',
					'line_item' : '<li>%title%<br/>\r\nBarcode: %barcode%  Call Number: %call_number%\r\n',
					'footer' : '</ol><hr />%PINES_CODE% %TODAY_TRIM%<br/>\r\n<br/>\r\n',
				}, 
				'bill_payment' : {
					'type' : 'payment',
					'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!<br/>A receipt of your  transaction:<hr/> <table width="100%"> <tr> <td>Original Balance:</td> <td align="right">$%original_balance%</td> </tr> <tr> <td>Payment Method:</td> <td align="right">%payment_type%</td> </tr> <tr> <td>Payment Received:</td> <td align="right">$%payment_received%</td> </tr> <tr> <td>Payment Applied:</td> <td align="right">$%payment_applied%</td> </tr> <tr> <td>Change Given:</td> <td align="right">$%change_given%</td> </tr> <tr> <td>Credit Given:</td> <td align="right">$%credit_given%</td> </tr> <tr> <td>New Balance:</td> <td align="right">$%new_balance%</td> </tr> </table> <p> Note: %note% </p> <p> Specific bills: <blockquote>',
					'line_item' : 'Bill #%bill_id%  Received: $%payment%<br />',
					'footer' : '</blockquote> </p> <hr />%PINES_CODE% %TODAY_TRIM%<br/> <br/> ',
				},
				'bills_historical' : {
					'type' : 'bills',
					'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!<br/>You had the following bills:<hr/><ol>',
					'line_item' : '<dt><b>Bill #%id%</b></dt> <dd> <table> <tr valign="top"><td>Date:</td><td>%xact_start%</td></tr> <tr valign="top"><td>Type:</td><td>%xact_type%</td></tr> <tr valign="top"><td>Last Billing:</td><td>%last_billing_type%<br/>%last_billing_note%</td></tr> <tr valign="top"><td>Total Billed:</td><td>$%total_owed%</td></tr> <tr valign="top"><td>Last Payment:</td><td>%last_payment_type%<br/>%last_payment_note%</td></tr> <tr valign="top"><td>Total Paid:</td><td>$%total_paid%</td></tr> <tr valign="top"><td><b>Balance:</b></td><td><b>$%balance_owed%</b></td></tr> </table><br/>',
					'footer' : '</ol><hr />%PINES_CODE% %TODAY_TRIM%<br/>\r\n<br/>\r\n',
				}, 
				'bills_current' : {
					'type' : 'bills',
					'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!<br/>You have the following bills:<hr/><ol>',
					'line_item' : '<dt><b>Bill #%id%</b></dt> <dd> <table> <tr valign="top"><td>Date:</td><td>%xact_start%</td></tr> <tr valign="top"><td>Type:</td><td>%xact_type%</td></tr> <tr valign="top"><td>Last Billing:</td><td>%last_billing_type%<br/>%last_billing_note%</td></tr> <tr valign="top"><td>Total Billed:</td><td>$%total_owed%</td></tr> <tr valign="top"><td>Last Payment:</td><td>%last_payment_type%<br/>%last_payment_note%</td></tr> <tr valign="top"><td>Total Paid:</td><td>$%total_paid%</td></tr> <tr valign="top"><td><b>Balance:</b></td><td><b>$%balance_owed%</b></td></tr> </table><br/>',
					'footer' : '</ol><hr />%PINES_CODE% %TODAY_TRIM%<br/>\r\n<br/>\r\n',
				}, 
				'offline_checkin' : {
					'type' : 'offline_checkin',
					'header' : 'You checked in the following items:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%\r\n',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
				'offline_renew' : {
					'type' : 'offline_renew',
					'header' : 'You renewed the following items:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%\r\n',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
				'offline_inhouse_use' : {
					'type' : 'offline_inhouse_use',
					'header' : 'You marked the following in-house items used:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%\r\nUses: %count%',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
				'holds' : {
					'type' : 'holds',
					'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!<br/>\r\nYou have the following titles on hold:<hr/><ol>',
					'line_item' : '<li>%title%\r\n',
					'footer' : '</ol><hr />%PINES_CODE% %TODAY_TRIM%<br/>\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%<br/>\r\n<br/>\r\n',
				} 
			}; 

			obj.stash( 'print_list_templates', 'print_list_types' );
		}
	},

	'network_retrieve' : function() {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		var obj = this;


		JSAN.use('util.file'); var file = new util.file('print_list_templates');
		obj.print_list_defaults();
		if (file._file.exists()) {
			try {
				var x = file.get_object();
				if (x) {
					for (var i in x) {
						obj.print_list_templates[i] = x[i];
					}
					obj.stash('print_list_templates');
				}
			} catch(E) {
				alert(E);
			}
		}
		file.close();

		JSAN.use('util.file');
		JSAN.use('util.functional');
		JSAN.use('util.fm_utils');

		function gen_fm_retrieval_func(classname,data) {
			var app = data[0]; var method = data[1]; var params = data[2]; var cacheable = data[3];
			return function () {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

				function convert() {
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					try {
						if (obj.list[classname].constructor.name == 'Array') {
							obj.hash[classname] = 
								util.functional.convert_object_list_to_hash(
									obj.list[classname]
								);
						}
					} catch(E) {

						obj.error.sdump('D_ERROR',E + '\n');
					}

				}

				try {
					var level = obj.error.sdump_levels.D_SES_RESULT;
					if (classname == 'aou' || classname == 'my_aou')
						obj.error.sdump_levels.D_SES_RESULT = false;
					var robj = obj.network.request( app, method, params);
					if (!robj || robj.ilsevent) {
						obj.error.standard_unexpected_error_alert('The staff client failed to retrieve expected data from this call, "' + method + '"',robj);
						throw(robj);
					}
					obj.list[classname] = robj;
					obj.error.sdump_levels.D_SES_RESULT = level;
					convert();
					// if cacheable, store an offline copy
					/* FIXME -- we're going to revisit caching and do it differently
					if (cacheable) {
						var file = new util.file( classname );
						file.set_object( obj.list[classname] );
					}
					*/

				} catch(E) {
					// if cacheable, try offline
					if (cacheable) {
						/* FIXME -- we're going to revisit caching and do it differently
						try {
							var file = new util.file( classname );
							obj.list[classname] = file.get_object(); file.close();
							convert();
						} catch(E) {
							throw(E);
						}
						*/
						throw(E); // for now
					} else {
						throw(E); // for now
					}
				}
			}
		}

		this.chain = [];

		this.chain.push(
			function() {
				var f = gen_fm_retrieval_func(
					'au',
					[
						api.FM_AU_RETRIEVE_VIA_SESSION.app,
						api.FM_AU_RETRIEVE_VIA_SESSION.method,
						[ obj.session.key ],
						false
					]
				);
				try {
					f();
				} catch(E) {
					var error = 'Error: ' + js2JSON(E);
					obj.error.sdump('D_ERROR',error);
					throw(E);
				}
				obj.list.au = [ obj.list.au ];
			}
		);

		this.chain.push(
			function() {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				var f = gen_fm_retrieval_func(
					'my_asv',
					[
						api.FM_ASV_RETRIEVE_REQUIRED.app,
						api.FM_ASV_RETRIEVE_REQUIRED.method,
						[ obj.session.key ],
						true
					]
				);
				try {
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					f();
				} catch(E) {
					var error = 'Error: ' + js2JSON(E);
					obj.error.sdump('D_ERROR',error);
					throw(E);
				}
			}
		);

		this.chain.push(
			function() {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				var f = gen_fm_retrieval_func(
					'asv',
					[
						api.FM_ASV_RETRIEVE.app,
						api.FM_ASV_RETRIEVE.method,
						[ obj.session.key ],
						true
					]
				);
				try {
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					f();
				} catch(E) {
					var error = 'Error: ' + js2JSON(E);
					obj.error.sdump('D_ERROR',error);
					throw(E);
				}
			}
		);

		obj.error.sdump('D_DEBUG','_fm_objects = ' + js2JSON(this._fm_objects) + '\n');

		for (var i in this._fm_objects) {
			this.chain.push( gen_fm_retrieval_func(i,this._fm_objects[i]) );
		}

		// The previous org_tree call returned a tree, not a list or hash.
		this.chain.push(
			function () {
				obj.tree.aou = obj.list.aou;
				obj.list.aou = util.fm_utils.flatten_ou_branch( obj.tree.aou );
				obj.hash.aou = util.functional.convert_object_list_to_hash( obj.list.aou );
			}
		);

		// Do this after we get the user object
		this.chain.push(

			function() {

				gen_fm_retrieval_func('my_aou', 
					[ 
						api.FM_AOU_RETRIEVE_RELATED_VIA_SESSION.app,
						api.FM_AOU_RETRIEVE_RELATED_VIA_SESSION.method,
						[ obj.session.key, obj.list.au[0].ws_ou() ], /* use ws_ou and not home_ou */
						true
					]
				)();
			}
		);

		this.chain.push(

			function () {

				gen_fm_retrieval_func( 'my_actsc', 
					[ 
						api.FM_ACTSC_RETRIEVE_VIA_AOU.app,
						api.FM_ACTSC_RETRIEVE_VIA_AOU.method,
						[ obj.session.key, obj.list.au[0].ws_ou() ],
						true
					]
				)();
			}
		);

		this.chain.push(

			function () {

				gen_fm_retrieval_func( 'my_asc', 
					[ 
						api.FM_ASC_RETRIEVE_VIA_AOU.app,
						api.FM_ASC_RETRIEVE_VIA_AOU.method,
						[ obj.session.key, obj.list.au[0].ws_ou() ],
						true
					]
				)();
			}
		);


		this.chain.push(
			function() {
				var f = gen_fm_retrieval_func(
					'cnct',
					[
						api.FM_CNCT_RETRIEVE.app,
						api.FM_CNCT_RETRIEVE.method,
						[ obj.list.au[0].ws_ou() ], 
						false
					]
				);
				try {
					f();
				} catch(E) {
					var error = 'Error: ' + js2JSON(E);
					obj.error.sdump('D_ERROR',error);
					throw(E);
				}
			}
		);


		if (typeof this.on_complete == 'function') {

			this.chain.push( this.on_complete );
		}
		JSAN.use('util.exec'); this.exec = new util.exec();
		this.exec.on_error = function(E) { 
		
			if (typeof obj.on_error == 'function') {
				obj.on_error();
			} else {
				alert('oops: ' + E ); 
			}

			return false; /* break chain */
		}

		this.exec.chain( this.chain );

	}
}

dump('exiting OpenILS/data.js\n');
