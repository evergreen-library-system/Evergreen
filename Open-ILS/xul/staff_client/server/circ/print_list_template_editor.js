dump('entering print_list_template_editor.js\n');

if (typeof circ == 'undefined') circ = {};
circ.print_list_template_editor = function (params) {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.error'); this.error = new util.error();
	} catch(E) {
		dump('print_list: ' + E + '\n');
	}
}

circ.print_list_template_editor.prototype = {

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

			var obj = this;

			obj.session = params['session'];

			JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

			if (typeof obj.data.print_list_templates == 'undefined') {
				obj.data.print_list_types = [ 'items', 'holds', 'patrons' ];
				obj.data.print_list_templates = { 
					'items_out' : {
						'type' : 'items',
						'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou have the following items:<hr/><ol>',
						'line_item' : '<li>%title: 50%\r\nBarcode: %barcode% Due: %due_date%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%',
					}, 
					'checkout' : {
						'type' : 'items',
						'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou checked out the following items:<hr/><ol>',
						'line_item' : '<li>%title%\r\nBarcode: %barcode% Due: %due_date%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%',
					}, 
					'checkin' : {
						'type' : 'items',
						'header' : 'You checked in the following items:<hr/><ol>',
						'line_item' : '<li>%title%\r\nBarcode: %barcode%  Call Number: %call_number%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\n',
					}, 
					'holds' : {
						'type' : 'holds',
						'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou have the following titles on hold:<hr/><ol>',
						'line_item' : '<li>%title%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%',
					} 
				}; 

				obj.data.stash( 'print_list_templates', 'print_list_types' );
			}

			obj.controller_init();
			obj.controller.render(); obj.controller.view.template_name_menu.focus();

		} catch(E) {
			alert('init: ' + E);
			this.error.sdump('D_ERROR','print_list.init: ' + E + '\n');
		}
	},

	'controller_init' : function() {
		try {
			var obj = this;
			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'sample' : [ ['command'], function() { } ],
						'header' : [ ['change'], function() { obj.preview(); } ],
						'line_item' : [ ['change'], function() { obj.preview(); } ],
						'footer' : [ ['change'], function() { obj.preview(); } ],
						'preview' : [
							['command'],
							function() {
							}
						],
						'save' : [
							['command'],
							function() {
								obj.save_template( obj.controller.view.template_name_menu.value );
							}
						],
						'delete' : [
							['command'],
							function() {
								alert( 'not yet implemented' );
							}
						],
						'macros' : [
							['command'],
							function() {
								try {
									JSAN.use('util.functional');
									var template_type = obj.controller.view.template_type_menu.value;
									var macros;
									switch(template_type) {
										case 'items':
											JSAN.use('circ.util');
											macros = util.functional.map_list(
												circ.util.columns( {} ),
												function(o) {
													return '%' + o.id + '%';
												}
											);
										break;
										case 'holds':
											JSAN.use('circ.util');
											macros = util.functional.map_list(
												circ.util.hold_columns( {} ),
												function(o) {
													return '%' + o.id + '%';
												}
											);
										break;
										case 'patrons':
											JSAN.use('patron.util');
											macros = util.functional.map_list(
												patron.util.columns( {} ),
												function(o) {
													return '%' + o.id + '%';
												}
											);
										break;
									}
									var macro_string = macros.join(', ');
									JSAN.use('util.window');
									var win = new util.window();
									win.open('data:text/html,'
										+ window.escape(
											'<html style="width: 600; height: 400;">'
											+ '<head><title>Template Macros</title></head>'
											+ '<body onload="document.getElementById(\'btn\').focus()">'
											+ '<h1>General:</h1>'
											+ '<p>%PINES_CODE%, %TODAY%, %STAFF_FIRSTNAME%, %STAFF_LASTNAME%, '
											+ '%PATRON_FIRSTNAME%, %LIBRARY%</p>'
											+ '<h1>For type: '
											+ template_type + '</h1>'
											+ '<p>' + macro_string + '</p>'
											+ '<button id="btn" onclick="window.close()">Close Window</button>'
											+ '</body></html>'
										), 'title', 'chrome,resizable');
								} catch(E) {
									alert(E);
								}
							}
						],
						'template_name_menu_placeholder' : [
							['render'],
							function(e) {
								return function() {
									JSAN.use('util.widgets'); JSAN.use('util.functional');
									util.widgets.remove_children(e);
									var ml = util.widgets.make_menulist(
										util.functional.map_object_to_list(
											obj.data.print_list_templates,
											function(o,i) { return [i,i]; }
										)
									);
									ml.setAttribute('id','template_name_menu');
									ml.setAttribute('editable','true');
									ml.setAttribute('flex','1');
									e.appendChild(ml);
									obj.controller.view.template_name_menu = ml;
									ml.addEventListener(
										'command',
										function(ev) {
											var tmp = obj.data.print_list_templates[ ev.target.value ];
											obj.controller.view.template_type_menu.value = tmp.type;
											obj.controller.view.header.value = tmp.header;
											obj.controller.view.line_item.value = tmp.line_item;
											obj.controller.view.footer.value = tmp.footer;
										},
										false
									);
									setTimeout(
										function() {
											var tmp = obj.data.print_list_templates[ ml.value ];
											obj.controller.view.template_type_menu.value = tmp.type;
											obj.controller.view.header.value = tmp.header;
											obj.controller.view.line_item.value = tmp.line_item;
											obj.controller.view.footer.value = tmp.footer;
										}, 0
									);
								}
							}
						],
						'template_type_menu_placeholder' : [
							['render'],
							function(e) {
								return function() {
									JSAN.use('util.widgets'); JSAN.use('util.functional');
									util.widgets.remove_children(e);
									var ml = util.widgets.make_menulist(
										util.functional.map_list(
											obj.data.print_list_types,
											function(o) { return [o,o]; }
										)
									);
									ml.setAttribute('id','template_types_menu');
									e.appendChild(ml);
									obj.controller.view.template_type_menu = ml;
								}
							}
						],

					}
				}
			);
		} catch(E) {
			alert('controller_init: ' + E );
		}
	},

	'preview' : function (name) { 
		var params = { 
			'au' : new au(), 
			'lib' : this.data.list.au[0].home_ou(),
			'staff' : this.data.list.au[0],
			'header' : this.controller.view.header.value,
			'line_item' : this.controller.view.line_item.value,
			'footer' : this.controller.view.footer.value,
			'type' : this.controller.view.template_type_menu.value,
			'list' : this.test_list[ this.controller.view.template_type_menu.value ].dump(),
			'sample_view' : this.controller.view.sample,
		};
		this.print( params );
	},

	'save_template' : function(name) {
		this.data.print_list_templates[name].header = this.controller.view.header.value;
		this.data.print_list_templates[name].line_item = this.controller.view.line_item.value;
		this.data.print_list_templates[name].footer = this.controller.view.footer.value;
		this.data.print_list_templates[name].type = this.controller.view.template_type_menu.value;
		this.data.stash( 'print_list_templates' );
		alert('Template Saved');
	},

	'print' : function(params) {
	},
}

dump('exiting print_list_template_editor.js\n');
