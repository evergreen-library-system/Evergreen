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
			this.test_patron = new au();
			this.test_patron.family_name('Doe');
			this.test_patron.first_given_name('John');
			this.test_card = new ac();
			this.test_card.barcode('123456789');
			this.test_patron.card( this.test_card );

			this.test_list = {
			
				'items' : { 'dump' : function() { return JSON2js('[["1858348","421","268297","31001000418112","AC KRENTZ","1","Stacks","Normal","ARL-ATH","Normal","Yes","Yes","Yes","No","No","0","18","","","2006-02-13 15:31:30.730986-05","","2006-02-27","Deep waters ","Krentz, Jayne Ann.","","0671575236 :","p1997","Simon & Schuster Audio","PIN01074166   ","1","Checked out","???","???"]]'); } },
				'holds' : { 'dump' : function() { return; } },
				'patrons' : { 'dump' : function() { return; } },
				'offline_checkout' : { 'dump' : function() { return; } },
				'offline_checkin' : { 'dump' : function() { return; } },
				'offline_renew' : { 'dump' : function() { return; } },
				'offline_inhouse_use' : { 'dump' : function() { return; } },
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
								obj.preview();
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

	'preview' : function () { 
		try {
			var params = { 
				'patron' : this.test_patron, 
				'lib' : this.data.hash.aou[ this.data.list.au[0].ws_ou() ],
				'staff' : this.data.list.au[0],
				'header' : this.controller.view.header.value,
				'line_item' : this.controller.view.line_item.value,
				'footer' : this.controller.view.footer.value,
				'type' : this.controller.view.template_type_menu.value,
				'list' : this.test_list[ this.controller.view.template_type_menu.value ].dump(),
				'sample_frame' : this.controller.view.sample,
			};
			JSAN.use('util.print'); var print = new util.print();
			print.tree_list( params );
		} catch(E) {
			this.error.sdump('D_ERROR','preview: ' + E);
			alert('preview: ' + E);
		}
	},

	'save_template' : function(name) {
		var obj = this;
		this.data.print_list_templates[name].header = this.controller.view.header.value;
		this.data.print_list_templates[name].line_item = this.controller.view.line_item.value;
		this.data.print_list_templates[name].footer = this.controller.view.footer.value;
		this.data.print_list_templates[name].type = this.controller.view.template_type_menu.value;
		this.data.stash( 'print_list_templates' );
		alert('Template Saved\n' + js2JSON(obj.data.print_list_templates[name]));
	},

}

dump('exiting print_list_template_editor.js\n');
