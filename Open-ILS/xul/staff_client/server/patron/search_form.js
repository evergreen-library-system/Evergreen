dump('entering patron/search_form.js\n');

if (typeof patron == 'undefined') patron = {};
patron.search_form = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.w = window;
}

patron.search_form.prototype = {

	'init' : function( params ) {

		var obj = this;

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert($("commonStrings").getString('common.unimplemented')); }
					],
					'cmd_patron_search_submit' : [
						['command'],
						function() {
							obj.submit();
						}
					],
					'cmd_patron_search_clear' : [
						['command'],
						function() { 
							obj.controller.render(); 
							window.xulG.clear_left_deck();
						}
					],
					'family_name' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.family_name) {
									e.setAttribute('value',params.query.family_name);
									e.value = params.query.family_name;
								} else {
									e.value = '';
								}
							};
						}
					],
					'first_given_name' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.first_given_name) {
									e.setAttribute('value',params.query.first_given_name);
									e.value = params.query.first_given_name;
								} else {
									e.value = '';
								}
							};
						}
					],
					'second_given_name' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.second_given_name) {
									e.setAttribute('value',params.query.second_given_name);
									e.value = params.query.second_given_name;
								} else {
									e.value = '';
								}
							};
						}
					],
					'alias' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.alias) {
									e.setAttribute('value',params.query.alias);
									e.value = params.query.alias;
								} else {
									e.value = '';
								}
							};
						}
					],
					'email' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.email) {
									e.setAttribute('value',params.query.email);
									e.value = params.query.email;
								} else {
									e.value = '';
								}
							};
						}
					],
					'phone' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.phone) {
									e.setAttribute('value',params.query.phone);
									e.value = params.query.phone;
								} else {
									e.value = '';
								}
							};
						}
					],
					'ident' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.ident) {
									e.setAttribute('value',params.query.ident);
									e.value = params.query.ident;
								} else if (params.query&&params.query.ident_value) {
									e.setAttribute('value',params.query.ident_value);
									e.value = params.query.ident_value;
								} else if (params.query&&params.query.ident_value2) {
									e.setAttribute('value',params.query.ident_value2);
									e.value = params.query.ident_value2;
								} else {
									e.value = '';
								}
							};
						}
					],
					'street1' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.street1) {
									e.setAttribute('value',params.query.street1);
									e.value = params.query.street1;
								} else {
									e.value = '';
								}
							};
						}
					],
					'street2' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.street2) {
									e.setAttribute('value',params.query.street2);
									e.value = params.query.street2;
								} else {
									e.value = '';
								}
							};
						}
					],
					'city' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.city) {
									e.setAttribute('value',params.query.city);
									e.value = params.query.city;
								} else {
									e.value = '';
								}
							};
						}
					],
					'state' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.state) {
									e.setAttribute('value',params.query.state);
									e.value = params.query.state;
								} else {
									e.value = '';
								}
							};
						}
					],
					'post_code' : [
						['render'],
						function(e) {
							return function() {
								if (params.query&&params.query.post_code) {
									e.setAttribute('value',params.query.post_code);
									e.value = params.query.post_code;
								} else {
									e.value = '';
								}
							};
						}
					],
					'inactive' : [ ['render'], function(e) { 
                            return function() {}; 
                        } 
                    ],
                    'search_depth' : [ ['render'],function(e) {
                            return function() {};
                        }
                    ],
				}
			}
		);

		obj.controller.render();
		var nl = document.getElementsByTagName('textbox');
		for (var i = 0; i < nl.length; i++) {
			nl[i].addEventListener('keypress',function(ev){
				if (ev.target.tagName != 'textbox') return;
				if (ev.keyCode == 13 /* enter */ || ev.keyCode == 77 /* enter on a mac */) setTimeout( function() { obj.submit(); }, 0);
			},false);
		}
		document.getElementById('family_name').focus();

        JSAN.use('util.file'); JSAN.use('util.widgets'); JSAN.use('util.functional');
        util.widgets.remove_children(obj.controller.view.search_depth);
        var ml = util.widgets.make_menulist(
            util.functional.map_list( obj.OpenILS.data.list.aout, 
                function(el,idx) {
                    return [ el.opac_label(), el.depth() ]
                }
            ).sort(
                function(a,b) {
                    if (a[1] < b[1]) return -1;
                    if (a[1] > b[1]) return 1;
                    return 0;
                }
            )
        );
        ml.addEventListener('command', function() {
                ml.parentNode.setAttribute('value',ml.value);
                var file = new util.file('patron_search_prefs.'+obj.OpenILS.data.server_unadorned);
                util.widgets.save_attributes(file, { 'search_depth_ml' : [ 'value' ], 'inactive' : [ 'value' ] });
            }, false
        );
        ml.setAttribute('id','search_depth_ml');
        obj.controller.view.search_depth.appendChild(ml);

		var file = new util.file('patron_search_prefs.'+obj.OpenILS.data.server_unadorned);
		util.widgets.load_attributes(file);
		ml.value = ml.getAttribute('value');
		if (! ml.value) {
			ml.value = 0
			ml.setAttribute('value',ml.value);
		}

        var cb = obj.controller.view.inactive;
        cb.addEventListener('command',function() { 
                cb.setAttribute('value',cb.checked ? "true" : "false");
                var file = new util.file('patron_search_prefs.'+obj.OpenILS.data.server_unadorned);
                util.widgets.save_attributes(file, { 'search_depth_ml' : [ 'value' ], 'inactive' : [ 'value' ] });
            }, false
        );
        cb.checked = cb.getAttribute('value') == "true" ? true : false;

	},

	'on_submit' : function(q) {
		var msg = 'Query = ' + q;
		this.error.sdump('D_PATRON', msg);
	},

	'submit' : function() {
		window.xulG.clear_left_deck();
		var obj = this;
		var query = {};
		for (var i = 0; i < obj.controller.render_list.length; i++) {
    		var id = obj.controller.render_list[i][0];
    		var node = document.getElementById(id);
			if (node && node.value != '') {
				if (id == 'inactive') {
					query[id] = node.getAttribute('value');
					obj.error.sdump('D_DEBUG','id = ' + id + '  value = ' + node.getAttribute('value') + '\n');
                } else {
                    if (id == 'search_depth') {
                        query[id] = node.firstChild.getAttribute('value'); 
    				} else {
     					var value = node.value.replace(/^\s+/,'').replace(/[\\\s]+$/,'');
    					//value = value.replace(/\d/g,'');
    					switch(id) {
    						case 'family_name' :
    						case 'first_given_name' :
    						case 'second_given_name' :
    							value = value.replace(/^\W+/g,'').replace(/\W+$/g,'');
    						break;
    					}
    					if (value != '') {
    						query[id] = value;
    						obj.error.sdump('D_DEBUG','id = ' + id + '  value = ' + value + '\n');
    					}
    				}
                }
			}
		}
		if (typeof obj.on_submit == 'function') {
			obj.on_submit(query);
		}
		if (typeof window.xulG == 'object' 
			&& typeof window.xulG.on_submit == 'function') {
			obj.error.sdump('D_PATRON','patron.search_form: Calling external .on_submit()\n');
			window.xulG.on_submit(query);
		} else {
			obj.error.sdump('D_PATRON','patron.search_form: No external .on_query()\n');
		}
	},

}

dump('exiting patron/search_form.js\n');
