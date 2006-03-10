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
			
				'items' : { 'dump' : function() { return JSON2js('[["1858348","421","268297","31001000418112","AC KRENTZ","1","???","Normal","???","Normal","0","0","18","","","2006-02-13 15:31:30.730986-05","","2006-02-27","Deep waters","Krentz, Jayne Ann.","1","???","???","???"],["3524184","462","???","nc10","Not Cataloged","","???","Normal","???","Normal","0","0","0","","","2006-02-16 01:00:44.84216-05","","2006-03-01","temp title","temp author","2","???","???","???"],["3524178","487","???","nc1","Not Cataloged","","???","Normal","???","Normal","0","0","0","","","2006-02-16 11:52:51.065944-05","","2006-03-02","title1","author1","2","???","???","???"]]'); } },
				'holds' : { 'dump' : function() { return JSON2js('[["2005-11-18","","","T","Athens-Clarke County Library","ARL-ATH","???","demo@demoland.tv","","","","18","111-222-3344","2006-02-16 03:33:24.90493-05","3","0","183324","3","WATER GARDENS (FOR YOUR GARDEN) PB","Spier, Carol."],["2005-11-22","","","T","Athens-Clarke County Library","ARL-ATH","33207004527158","demo@demoland.tv","","","","25","111-222-3344","2006-02-16 03:33:27.754555-05","3","0","278434","3","Harry Potter and the sorcerer\'s stone","Rowling, J. K."],["2005-11-22","2006-02-09 21:29:09.575124-05","","T","Athens-Clarke County Library","ARL-ATH","33207000946790","demo@demoland.tv","","","","26","111-222-3344","2006-02-09 21:03:11.938293-05","3","0","352139","3","Shakespeare the man","Rowse, A. L. "],["2005-11-22","","","T","Athens-Clarke County Library","ARL-ATH","???","demo@demoland.tv","","","","27","111-222-3344","2006-02-16 03:33:39.35158-05","3","0","277202","3","Costa Rica","Morrison, Marion."],["2005-11-22","","","T","Bogart Branch Library","ARL-BOG","???","demo@demoland.tv","","","","29","111-222-3344","2006-02-16 03:33:41.297713-05","3","0","366540","3","On leaving Charleston","Ripley, Alexandra."],["2005-11-24","","","T","Athens-Clarke County Library","ARL-ATH","???","demo@demoland.tv","","","","30","111-222-3344","2006-02-16 03:33:41.697186-05","3","0","216351","3","Cats! Cats! Cats!","Wiseman, Bernard."],["2005-12-09","","","T","Athens-Clarke County Library","ARL-ATH","???","demo@demoland.tv","","","","32","111-222-3344","2006-02-16 03:33:41.970716-05","3","0","313569","3","Water","Cooper, Jason"],["2006-02-16","2006-02-16 06:23:19.602866-05","","T","Athens-Clarke County Library","ARL-ATH","a1115b1","demo@demoland.tv","","","","65","111-222-3345","2006-02-16 06:22:11.49379-05","14","0","200839","3","Water all around","Pine, Tillie S."]]'); } },
				'patrons' : { 'dump' : function() { return JSON2js('[["090909090","demo3","Good","Users","Yes","6","Airman","Demo3","Demo3","D","III","","0","2005-11-22","2008-11-22","ECGR-MIDVL","0","","","","demo2@open-ils.org","1980-04-03","Drivers Licence","9898888777","???","","1"],["123321123321123","miker2","Good","Patrons","Yes","21","mr","Rylander","Mike","E","IIX","","0","2006-02-16","2006-01-01","ARL-BOG","0","770-222-5555","","","miker@example.com","1979-01-22","State ID","0987654321","???","","1"],["123456789","demo","Good","Staff","Yes","3","Mr.","Joe","Demo","J","","test","0","2005-11-15","2008-11-15","ARL-ATH","978.38","111-222-3345","222-333-4455","","demo@demoland.tv","1976-10-24","Drivers Licence","888888","???","","1"],["user2","user2","Good","Patrons","Yes","17","","User","Jim","","","","0","2006-02-13","2009-02-13","ARL-BOG","0","404","","","","2005-12-12","Drivers Licence","1234","???","","1"],["18009999999","animalmother","Good","Patrons","Yes","12","","Mother","Animal","","","","0","2006-02-13","2008-02-15","ARL-BOG","0","444-333-2222","","","animalmother@fullmetaljacket.net","1969-01-02","SSN","123456789","???","","1"],["staff3","staff3","Good","Circulators","Yes","15","","staff","circ","","","","0","2006-02-13","2009-02-13","ARL-BKM","0","777","","","","2005-12-12","Drivers Licence","n/a","???","","1"],["staff2","staff2","Good","Circulators","Yes","14","","Staff","Circ","","","","0","2006-02-13","2009-02-13","ARL-BOG","0","777","","","","2005-12-12","Drivers Licence","n/a","???","","1"],["11223344","miker","Good","Patrons","Yes","8","Mr","rylander","mike","","","","0","2005-12-19","2008-12-19","ARL-EAST","0","12123412","","","mrylander@example.com","1979-01-22","Voter Card","123456","???","","1"],["987654321","erickson","Good","Operations Manager","Yes","4","","Erickson","Bill","S","","","1","2005-11-18","2008-11-18","ARL-ATH","5","111-444-7777","1-800-999-9998","","bill@mastashake.org","1976-10-24","Voter Card","999999999999","???","","1"],["user4","user4","Good","Patrons","Yes","34","","Nimble","Jack","B","","","0","2006-02-16","2009-02-16","ARL-ATH","0","404","","","","2000-10-10","Drivers Licence","123","???","","1"],["user3","user3","Good","Patrons","Yes","18","","User","Jane","","","","0","2006-02-13","2009-02-13","ARL-BKM","0","404","","","","2005-12-12","Drivers Licence","12345","???","","1"],["user1","user1","Good","Patrons","Yes","16","","User","Joe","","","","0","2006-02-13","2009-02-13","ARL-ATH","0","404","404","","","2005-12-12","Drivers Licence","123","???","","1"],["staff1","staff1","Good","Circulators","Yes","13","","Staff","Circ","","","","0","2006-02-13","2009-02-13","ARL-ATH","0","777","","","","2005-12-12","Drivers Licence","n/a","???","","1"],["1122332211","demo2","Good","Users","Yes","5","Advisor","Jones","Demo2","D","","","0","2005-11-22","2008-11-22","CPRL-R","0","111-222-3333","","","demo2@open-ils.org","1980-05-02","Drivers Licence","0009990000","???","","1"]]'); } },

			}

			if (typeof obj.data.print_list_templates == 'undefined') {
				obj.data.print_list_types = [ 'items', 'holds', 'patrons' ];
				obj.data.print_list_templates = { 
					'items_out' : {
						'type' : 'items',
						'header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou have the following items:<hr/><ol>',
						'line_item' : '<li>%title%\r\nBarcode: %barcode% Due: %due_date%\r\n',
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
		this.data.print_list_templates[name].header = this.controller.view.header.value;
		this.data.print_list_templates[name].line_item = this.controller.view.line_item.value;
		this.data.print_list_templates[name].footer = this.controller.view.footer.value;
		this.data.print_list_templates[name].type = this.controller.view.template_type_menu.value;
		this.data.stash( 'print_list_templates' );
		alert('Template Saved');
	},

}

dump('exiting print_list_template_editor.js\n');
