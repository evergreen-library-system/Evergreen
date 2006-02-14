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
				obj.data.print_list_types = [ 'items', 'holds' ];
				obj.data.print_list_templates = { 
					'items_out' : {
						'type' : 'items',
						'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou have the following items:<hr/><ol>',
						'line_item' : '<li>%TITLE: 50%\r\nBarcode: %COPY_BARCODE% Due: %DUE_D%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%',
					}, 
					'checkout' : {
						'type' : 'items',
						'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou checked out the following items:<hr/><ol>',
						'line_item' : '<li>%TITLE%\r\nBarcode: %COPY_BARCODE% Due: %DUE_D%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%',
					}, 
					'checkin' : {
						'type' : 'items',
						'header' : 'You checked in the following items:<hr/><ol>',
						'line_item' : '<li>%TITLE%\r\nBarcode: %COPY_BARCODE%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\n',
					}, 
					'holds' : {
						'type' : 'holds',
						'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou have the following titles on hold:<hr/><ol>',
						'line_item' : '<li>%TITLE%\r\n',
						'footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%',
					} 
				}; 

				obj.data.stash( 'print_list_templates', 'print_list_types' );
			}

			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'header' : [ ['command'], function() {} ],
						'line_item' : [ ['command'], function() {} ],
						'footer' : [ ['command'], function() {} ],
						'preview' : [
							['command'],
							function() {
								alert( 'preview: ' + obj.controller.view.template_name_menu.value );
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
									ml.addEventListener(
										'command',
										function(ev) {
											alert(ev.target.value);
										},
										false
									);
								}
							}
						],

					}
				}
			);
			obj.controller.render(); obj.controller.view.template_name_menu.focus();

		} catch(E) {
			this.error.sdump('D_ERROR','print_list.init: ' + E + '\n');
		}
	},

	'test_template' : function (name) { 
		var params = { 
			'au' : test_patron, 
			'lib' : obj.data.list.au[0].home_ou(),
			'staff' : obj.data.list.au[0],
			'header' : document.getElementById(name + '_header_tb').value,
			'line_item' : document.getElementById(name + '_line_item_tb').value,
			'footer' : document.getElementById(name + '_footer_tb').value
		};
		this.print.print_list( params, sample_view );
	},

	'save_template' : function(name) {
		this.data.print_list_templates[name].header = this.controller.view.header.value;
		this.data.print_list_templates[name].line_item = this.controller.view.line_item.value;
		this.data.print_list_templates[name].footer = this.controller.view.footer.value;
		this.data.stash( 'print_list_templates' );
		alert('Template Saved');
	},
}

dump('exiting print_list_template_editor.js\n');
