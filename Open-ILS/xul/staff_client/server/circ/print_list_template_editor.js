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

			JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
			this.test_patron = new au();
			this.test_patron.family_name('Doe');
			this.test_patron.first_given_name('John');
			this.test_card = new ac();
			this.test_card.barcode('123456789');
			this.test_patron.card( this.test_card );

			this.test_data = {
				'payment' : {
					'original_balance' : '7.40',
					'payment_type' : 'Cash',
					'payment_received' : '10.00',
					'payment_applied' : '7.40',
					'change_given' : '2.60',
					'credit_given' : '0.00',
					'note' : "The patron's child paid this",
					'new_balance' : '0.00',
				},
			}

			this.test_list = {
			
				'items' : [["7608453","???","1497190","31033007616786","J 551.48 ARATO R","MGRL-RC","1","Stacks","Short","MGRL-RC","Low","Yes","Yes","Yes","No","No","0","19.95","","","???","???","???","???","World of water ","Arato, Rona.","","0778714160 (rlb : alk. paper)","c2005","Crabtree Pub. Co.","ocm55600795 ","???","???","Available","???","???","undefined",""],["7136201","???","1424085","31001000224056","YA ROWLING","ARL-ATH","3","Stacks","Short","ARL-ATH","Low","Yes","Yes","Yes","No","No","0","7.99","","","???","???","???","???","Harry Potter and the prisoner of Azkaban ","Rowling, J. K.","","0439136350 (hc)","1999","Arthur A. Levine Books","ocm41266045 ","???","???","Available","???","???","undefined",""],["6577928","???","1301532","31041005919235","975.8784 HAG","OHOOP-LADS","1","Stacks","Short","OHOOP-LADS","Low","Yes","Yes","Yes","No","No","0","10","","","???","???","???","???","Georgia genealogical sources series marriages 1869-1879, Appling County Georgia","Hageness, MariLee Beatty.","","","c1998","MLH Research","ocm49507123 ","???","???","Available","???","???","undefined",""]],
				'holds' : [["2006-05-13","2006-05-18 16:37:47.062916-04","","T","Athens-Clarke County Library","ARL-ATH","33207004749414","No","","","","7","999-999-9999","2006-05-15 00:37:28.269456-04","3","0","818781","3","Harry Potter and the goblet of fire ","Rowling, J. K.","Large print ed.","0786229276 (lg. print : hc : alk. paper)","2000","Thorndike Press","i0786229276"],["2006-05-16","2006-05-18 20:07:04.474747-04","","T","Athens-Clarke County Library","ARL-ATH","33207004347359","Yes","","","","8","777-777-7777","2006-05-18 16:52:23.866001-04","1000000","0","551071","1000524","Cats ","Arnold, Caroline.","","0822530325 (alk. paper)","1999","Lerner Publications","i0822530325"],["2006-05-17","2006-05-18 20:08:32.882203-04","","T","Athens-Clarke County Library","ARL-ATH","33207002398776","Yes","","","","28","999-999-9999","2006-05-18 16:52:58.020117-04","1000000","0","1274439","3","Tortilla Flat ","Steinbeck, John","","0140042407 (pbk.) :","1986, c1935","Penguin Books","a2095783"],["2006-05-10","2006-05-20 21:02:57.318012-04","","T","Athens-Clarke County Library","ARL-ATH","33207003330208","No","","","","4","222-333-4444","2006-05-18 16:52:23.362607-04","3","0","315900","3","Spreadin\' rhythm around Black popular songwriters, 1880-1930","Jasen, David A.","","0028647424","c1998","Schirmer Books","i0028647424"],["2006-05-20","2006-05-20 21:11:42.124176-04","","T","Athens-Clarke County Library","ARL-ATH","33207001049453","Yes","","","","54","218-233-3757","2006-05-20 19:48:12.101796-04","1000000","0","323269","1000567","Foundation and empire ","Asimov, Isaac","","0893402109","1979","J. Curley","i0893402109"],["2006-05-20","2006-05-20 21:19:15.209143-04","","T","Athens-Clarke County Library","ARL-ATH","33207001502782","Yes","","","","63","218-233-3757","2006-05-20 19:48:37.645795-04","1000567","0","427831","1000567","The  Caine mutiny :  a novel of World War II","Wouk, Herman","","","1952 [c1951]","Doubleday","PIN24075557"],["2006-06-03","2006-06-07 17:03:32.676709-04","","V","Athens-Clarke County Library","ARL-ATH","No Copy","No","","","","135","999-999-9999","2006-06-05 23:45:18.078505-04","3","0","6592393","3","No Title?","No Author?","???","???","???","???","???"]],
				'bills' : [["248","Id = 3","grocery","-2.00","0.00","2.00","","Fee for copies","2006-05-27 22:56","","cash_payment","2006-06-10 17:01","2006-05-27",""],["239","Id = 3","circulation","17.00","17.00","0.00","SYSTEM GENERATED","Lost Materials Processing Fee","2006-05-27 22:07","",""," ","2006-05-26",""],["173","Id = 3","grocery","1.00","17.25","16.25","","Lost materials","2006-05-20 16:36","","cash_payment","2006-05-27 01:31","2006-05-20",""]],
				'payment' : [ [333, '2.23'], [367, '5.17' ] ],
				'patrons' : [],
				'offline_checkout' : [],
				'offline_checkin' : [],
				'offline_renew' : [],
				'offline_inhouse_use' : [],
			}

			obj.controller_init();
			obj.controller.render(); obj.controller.view.template_name_menu.focus();

			obj.post_init();

		} catch(E) {
			alert('init: ' + E);
			this.error.sdump('D_ERROR','print_list.init: ' + E + '\n');
		}
	},

	'post_init' : function() {
		var obj = this;
		setTimeout(
			function() {
				var tmp = obj.data.print_list_templates[ obj.controller.view.template_name_menu.value ];
				obj.controller.view.template_type_menu.value = tmp.type;
				obj.controller.view.header.value = tmp.header;
				obj.controller.view.line_item.value = tmp.line_item;
				obj.controller.view.footer.value = tmp.footer;
				obj.preview();
			}, 0
		);
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
						'default' : [
							['command'],
							function() {
								obj.data.print_list_defaults();
								obj.post_init();
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
										case 'bills':
											JSAN.use('patron.util');
											macros = util.functional.map_list(
												patron.util.mbts_columns( {} ),
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
										case 'payment' : 
											macros = [ '%original_balance%', '%payment_received%', '%payment_applied%', '%payment_type%', '%change_given%', '%new_balance%', '%note%', '%bill_id%', '%payment%' ];
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
									//ml.setAttribute('editable','true');
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
											obj.preview();
										},
										false
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
									ml.setAttribute('disabled','true');
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
			var list = this.test_list[ this.controller.view.template_type_menu.value ];
			if (typeof list == 'undefined') list = [];
			var data = this.test_data[ this.controller.view.template_type_menu.value ];
			if (typeof data == 'undefined') data = {};

			var params = { 
				'patron' : this.test_patron, 
				'lib' : this.data.hash.aou[ this.data.list.au[0].ws_ou() ],
				'staff' : this.data.list.au[0],
				'header' : this.controller.view.header.value,
				'line_item' : this.controller.view.line_item.value,
				'footer' : this.controller.view.footer.value,
				'type' : this.controller.view.template_type_menu.value,
				'list' : list,
				'data' : data,
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
		obj.data.print_list_templates[name].header = obj.controller.view.header.value;
		obj.data.print_list_templates[name].line_item = obj.controller.view.line_item.value;
		obj.data.print_list_templates[name].footer = obj.controller.view.footer.value;
		obj.data.print_list_templates[name].type = obj.controller.view.template_type_menu.value;
		obj.data.stash( 'print_list_templates' );
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.file'); var file = new util.file('print_list_templates');
		file.set_object(obj.data.print_list_templates); file.close();
		alert('Template Saved\n' + js2JSON(obj.data.print_list_templates[name]));
	},

}

dump('exiting print_list_template_editor.js\n');
