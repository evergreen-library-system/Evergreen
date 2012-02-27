dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");

function removeReportAtom (args) {
	if (!args) args = {};

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];
	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var fields = getSelectedItems(tree);


	for (var i in fields) {
		var field = fields[i];
		var colname = field.firstChild.firstChild.nextSibling.getAttribute('label');
		var relation_alias = field.getAttribute('relation');

		delete rpt_rel_cache[relation_alias].fields[tabname][colname];
		if (tabname == 'dis_tab') {
			var _o_tmp = [];
			for each (var _o_col in rpt_rel_cache.order_by) {
				if (_o_col.relation == relation_alias && _o_col.field == colname) continue;
				_o_tmp.push( _o_col );
			}
			rpt_rel_cache.order_by = _o_tmp
		}

		with (rpt_rel_cache[relation_alias].fields) {
			if ( getKeys(dis_tab).length == 0 && getKeys(filter_tab).length == 0 && getKeys(aggfilter_tab).length == 0 )
				delete rpt_rel_cache[relation_alias];
		}
	}

	renderSources();

	return true;
}

function getSourceDefinition(aClass) {
	var class_obj = getIDLClass(aClass);
	return class_obj.getAttributeNS(persistNS,'tablename') || 
        '(' + class_obj.getElementsByTagNameNS(persistNS,'source_definition')[0].textContent + ')';
}

function addReportAtoms () {
	var nope = $( 'source-add' ).getAttribute('disabled');
	if (nope == 'true') return false;

	var class_tree = $('class-view');
	var transform_tree = $('trans-view');

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id')

	var items = getSelectedItems(class_tree);
	var transform = getSelectedItems(transform_tree)[0];

	var reltype = $('path-label').getAttribute('reltype');
	var class_label = $('path-label').value;
	var relation_alias = hex_md5(class_label);

	for (var i in items) {
		var item = items[i];

		var class_path = item.getAttribute('fullpath');
		var field_class = item.getAttribute('idlclass');
		var datatype = item.getAttribute('datatype');
		var colname = item.getAttribute('idlfield');
		var jointype = item.getAttribute('join');
		var field_label = item.firstChild.firstChild.getAttribute('label');

		var table_name = getSourceDefinition(field_class);

		if ( !rpt_rel_cache[relation_alias] ) {
			rpt_rel_cache[relation_alias] =
				{ label     : class_label,
				  alias     : relation_alias,
				  path      : class_path,
				  join      : jointype,
				  reltype   : reltype,
				  idlclass  : field_class,
				  table     : table_name,
				  fields    : { dis_tab : {}, filter_tab : {}, aggfilter_tab : {} }
				};
		}

		if ( !rpt_rel_cache[relation_alias].fields[tabname][colname] ) {
			rpt_rel_cache[relation_alias].fields[tabname][colname] =
				{ colname   : colname,
				  transform : (transform && transform.getAttribute('name')) || rpt_strings.TEMPLATE_CONF_BARE,
				  aggregate : transform && transform.getAttribute('aggregate'),
				  params    : transform && transform.getAttribute('params'),
				  transform_label: (transform && transform.getAttribute('alias')) || rpt_strings.TEMPLATE_CONF_RAW_DATA,
				  alias     : field_label,
				  join      : jointype,
				  datatype  : datatype,
				  op        : (datatype == 'array') ? '= any' : '=',
				  op_label  : rpt_strings.TEMPLATE_CONF_EQUALS,
				  op_value  : {}
				};

			if (!rpt_rel_cache.order_by)
				rpt_rel_cache.order_by = [];

			if (tabname == 'dis_tab')
				rpt_rel_cache.order_by.push( { relation : relation_alias, field : colname } );

		} else if (confirm(dojo.string.substitute( rpt_strings.TEMPLATE_CONF_CONFIRM_RESET, [field_label, class_label] )) ) {
			rpt_rel_cache[relation_alias].fields[tabname][colname] =
				{ colname   : colname,
				  transform : (transform && transform.getAttribute('name')) || rpt_strings.TEMPLATE_CONF_BARE,
				  aggregate : transform && transform.getAttribute('aggregate'),
				  params    : transform && transform.getAttribute('params'),
				  transform_label: (transform && transform.getAttribute('alias')) || rpt_strings.TEMPLATE_CONF_RAW_DATA,
				  alias     : field_label,
				  join      : jointype,
				  datatype  : datatype,
				  op        : '=',
				  op_label  : rpt_strings.TEMPLATE_CONF_EQUALS,
				  op_value  : {}
				};
		}
	}

	renderSources();

	return true;
}

function changeDisplayOrder (dir) {
	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var item = getSelectedItems(tree)[0];

	var item_pos = tree.view.selection.currentIndex;

	if (dir == 'u') {
		if ( item.previousSibling ) {
			item.parentNode.insertBefore( item, item.previousSibling );
			item_pos--;
		}
	} else if (dir == 'd') {
		if ( item.nextSibling ) {
			if (item.nextSibling.nextSibling ) item.parentNode.insertBefore( item, item.nextSibling.nextSibling );
			else item.parentNode.appendChild( item );
			item_pos++;
		}
	}
	
	rpt_rel_cache.order_by = [];
	var ordered_list = tree.getElementsByTagName('treeitem');
	for (var i = 0; i < ordered_list.length; i++) {
		rpt_rel_cache.order_by.push(
			{ relation : ordered_list[i].getAttribute('relation'),
			  field    : ordered_list[i].firstChild.firstChild.nextSibling.getAttribute('label')
			}
		);
	}

	tree.view.selection.select( item_pos );
	return true;
}

function alterColumnLabel () {
	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var item_pos = tree.view.selection.currentIndex;

	var item = getSelectedItems(tree)[0];
	var relation_alias = item.getAttribute('relation');

	var field = item.firstChild.firstChild;
	var colname = field.nextSibling.getAttribute('label');

	var new_label =	prompt( dojo.string.substitute(rpt_strings.TEMPLATE_CONF_PROMPT_CHANGE, [field.getAttribute("label")]) );

	if (new_label) {
		rpt_rel_cache[relation_alias].fields[tabname][colname].alias = new_label;
		renderSources(true);
		tree.view.selection.select( item_pos );
		tree.focus();
		tree.click();
	}

	return true;
}

function alterColumnTransform (trans) {

	var transform = OILS_RPT_TRANSFORMS[trans];

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var item_pos = tree.view.selection.currentIndex;
	var item =  getSelectedItems(tree)[0];
	var relation_alias = item.getAttribute('relation');

	var field = item.firstChild.firstChild;
	var colname = field.nextSibling.getAttribute('label');

	rpt_rel_cache[relation_alias].fields[tabname][colname].transform = trans;
	rpt_rel_cache[relation_alias].fields[tabname][colname].aggregate = transform.aggregate;
	rpt_rel_cache[relation_alias].fields[tabname][colname].params = transform.params;
	rpt_rel_cache[relation_alias].fields[tabname][colname].transform_label = transform.label;

	renderSources(true);
	tree.view.selection.select( item_pos );
	tree.focus();
	tree.click();

	$(tabname + '_trans_menu').hidePopup();
	return true;
}

function changeOperator (args) {

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var item_pos = tree.view.selection.currentIndex;
	var item = getSelectedItems(tree)[0];

	var relation_alias = item.getAttribute('relation');

	var field = item.firstChild.firstChild;
	var colname = field.nextSibling.getAttribute('label');

	rpt_rel_cache[relation_alias].fields[tabname][colname].op = args.op;
	rpt_rel_cache[relation_alias].fields[tabname][colname].op_label = args.label;

	renderSources(true);
	tree.view.selection.select( item_pos );
	tree.focus();
	tree.click();

	$(tabname + '_op_menu').hidePopup();
	return true;
}

function removeTemplateFilterValue () {

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var item_pos = tree.view.selection.currentIndex;
	var items = getSelectedItems(tree);

	for (var i in items) {
		var item = items[i];
		var relation_alias = item.getAttribute('relation');

		var field = item.firstChild.firstChild;
		var colname = field.nextSibling.getAttribute('label');

		rpt_rel_cache[relation_alias].fields[tabname][colname].op_value = {};
	}

	renderSources(true);
	tree.view.selection.select( item_pos );
	return true;
}

function timestampSetDate (obj, cal, date) {
	obj.op_value.value = date;
	obj.op_value.object = cal.date;
	obj.op_value.label = '"' + date + '"';

	renderSources(true);
	return true;
}

var __handler_cache;

function changeTemplateFilterValue () {

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var items = getSelectedItems(tree);

	var targetCmd = $( tabname + '_value_action' );

	targetCmd.menu = null;
	targetCmd.command = null;
	targetCmd.oncommand = null;
	targetCmd.removeEventListener( 'command', __handler_cache, true );

	for (var i in items) {
		var item = items[i];
		var relation_alias = item.getAttribute('relation');

		var field = item.firstChild.firstChild;
		var colname = field.nextSibling.getAttribute('label');

		var obj = rpt_rel_cache[relation_alias].fields[tabname][colname]
		var operation = OILS_RPT_FILTERS[obj.op];

		switch (obj.datatype) {
			case 'timestamp':
				var cal_popup = $('calendar-widget');

				while (cal_popup.firstChild) cal_popup.removeChild(cal_popup.lastChild);
				var calendar = new Calendar(
					0,
					obj.op_value.object,
					function (cal,date) { return timestampSetDate(obj,cal,date) },
					function (cal) { cal_popup.hidePopup(); cal.destroy(); return true; }
				);

				var format = OILS_RPT_TRANSFORMS[obj.transform].cal_format || '%Y-%m-%d';

				calendar.setDateFormat(format);
				calendar.create(cal_popup);

				targetCmd.menu = 'calendar-widget';

				break;

			case 'bool':

				function __bool_value_event_handler () {
					var state, answer;

					try {
						// get a reference to the prompt service component.
						var promptService = Components.classes["@mozilla.org/embedcomp/prompt-service;1"]
						                    .getService(Components.interfaces.nsIPromptService);

						// set the buttons that will appear on the dialog. It should be
						// a set of constants multiplied by button position constants. In this case,
						// three buttons appear, Save, Cancel and a custom button.
						var flags=promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_0 +
							promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_1 +
						        promptService.BUTTON_TITLE_CANCEL * promptService.BUTTON_POS_2;

						// display the dialog box. The flags set above are passed
						// as the fourth argument. The next three arguments are custom labels used for
						// the buttons, which are used if BUTTON_TITLE_IS_STRING is assigned to a
						// particular button. The last two arguments are for an optional check box.
						answer = promptService.select(
							window,
							rpt_strings.TEMPLATE_CONF_BOOLEAN_VALUE,
							rpt_strings.TEMPLATE_CONF_SELECT_CANCEL,
							2, [rpt_strings.TEMPLATE_CONF_TRUE, rpt_strings.TEMPLATE_CONF_FALSE], state
						);
					} catch (e) {
						answer = true;
						state = confirm(rpt_strings.TEMPLATE_CONF_CONFIRM_STATE);
						state ? state = 0 : state = 1;
					}

					if (answer) {
						if (state) {
							obj.op_value.value = 'f';
							obj.op_value.label = rpt_strings.TEMPLATE_CONF_FALSE;
						} else {
							obj.op_value.value = 't';
							obj.op_value.label = rpt_strings.TEMPLATE_CONF_TRUE;
						}
					}

					targetCmd.removeEventListener( 'command', __bool_value_event_handler, true );
					renderSources(true);
					tree.view.selection.select( item_pos );
					return true;
				}

				__handler_cache = __bool_value_event_handler;
				targetCmd.addEventListener( 'command', __bool_value_event_handler, true );

				break;

			default:


				var promptstring = rpt_strings.TEMPLATE_CONF_NO_MATCH;

				switch (obj.op) {
					case 'not between':
						promptstring = rpt_strings.TEMPLATE_CONF_NOT_BETWEEN;
						break;

					case 'between':
						promptstring = rpt_strings.TEMPLATE_CONF_BETWEEN;
						break;

					case 'not in':
						promptstring = rpt_strings.TEMPLATE_CONF_NOT_IN;
						break;

					case 'in':
						promptstring = rpt_strings.TEMPLATE_CONF_IN;
						break;

					default:
						promptstring = 	dojo.string.substitute( rpt_strings.TEMPLATE_CONF_DEFAULT, [obj.op_label]);
						break;
				}

				function __default_value_event_handler () {
					var _v;
					if (_v  = prompt( promptstring, obj.op_value.value || '' )) {
						switch (obj.op) {
							case 'between':
							case 'not between':
							case 'not in':
							case 'in':
								obj.op_value.value = _v.split(/\s*,\s*/);
								break;

							default:
								obj.op_value.value = _v;
								break;
						}

						obj.op_value.label = '"' + obj.op_value.value + '"';
					}

					targetCmd.removeEventListener( 'command', __default_value_event_handler, true );
					renderSources(true);
					tree.view.selection.select( item_pos );
					return true;
				}

				__handler_cache = __default_value_event_handler;
				targetCmd.addEventListener( 'command', __default_value_event_handler, true );

				break;
		}
	}

	return true;
}

function populateOperatorContext () {

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var items = getSelectedItems(tree);

	var dtypes = [];
	for (var i in items) {
		var item = items[i];
		dtypes.push( item.getAttribute('datatype') );
	}

	var menu = $(tabname + '_op_menu');
	while (menu.firstChild) menu.removeChild(menu.lastChild);

	for (var i in OILS_RPT_FILTERS) {
		var o = OILS_RPT_FILTERS[i];
        if (o.label) {
    		menu.appendChild(
	    		createMenuItem(
		    		{ label : o.label,
			    	  onmouseup : "changeOperator({op:'"+i+"',label:'"+o.label+"'})"
				    }
    			)
	    	);
        }

		if (o.labels) {
			var keys = getKeys(o.labels);
			for ( var k in keys ) {
				var key = keys[k];
				if ( grep(function(x){return key==x},dtypes).length ) {
					menu.appendChild(
						createMenuItem(
							{ label : o.labels[key],
							  onmouseup : "changeOperator({op:'"+i+"',label:'"+o.labels[key]+"'});"
							}
						)
					);
				}
			}
		}
	}
}

function populateTransformContext () {

	var active_tab = filterByAttribute(
		$('used-source-fields-tabbox').getElementsByTagName('tab'),
		'selected',
		'true'
	)[0];

	var tabname = active_tab.getAttribute('id');

	var tabpanel = $( tabname + 'panel' );
	var tree = tabpanel.getElementsByTagName('tree')[0];
	var items = getSelectedItems(tree);

	var transforms = {};
	for (var i in items) {
		var item = items[i];
		var dtype = item.getAttribute('datatype');
		var item_transforms = getTransforms({ datatype : dtype });

		for (var j in item_transforms) {
			transforms[item_transforms[j]] = OILS_RPT_TRANSFORMS[item_transforms[j]];
			transforms[item_transforms[j]].name = item_transforms[j];
		}
	}

	var transformList = [];
	for (var i in transforms) {
		transformList.push( transforms[i] );
	}

	transformList.sort( sortHashLabels );

	var menu = $(tabname + '_trans_menu');
	while (menu.firstChild) menu.removeChild(menu.lastChild);

	for (var i in transformList) {
		var t = transformList[i];

		if (tabname.match(/filter/)) {
			if (tabname.match(/^agg/)) {
				if (!t.aggregate) continue;
			} else {
				if (t.aggregate) continue;
			}
		}

		menu.appendChild(
			createMenuItem(
				{ aggregate : t.aggregate,
				  name : t.name,
				  alias : t.label,
				  label : t.label,
				  params : t.params,
				  onmouseup : "alterColumnTransform('"+t.name+"')"
				}
			)
		);
	}

	menu.parentNode.setAttribute('disabled','false');
	if (menu.childNodes.length == 0) {
		menu.parentNode.setAttribute('disabled','true');
	}
}


function renderSources (selected) {

	var tree = $('used-sources');
	var sources = $('used-sources-treetop');
	var tabs = $('used-source-fields-tabbox').getElementsByTagName('tab');

	if (!selected) {
		while (sources.firstChild) sources.removeChild(sources.lastChild);
	} else {
		selected = getSelectedItems(tree);
		if (!selected.length) {
			selected = undefined;
			while (sources.firstChild) sources.removeChild(sources.lastChild);
		}
	}

	for (var j = 0; j < tabs.length; j++) {
		var tab = tabs[j];
		var tabname = tab.getAttribute('id')
		var tabpanel = $( tab.getAttribute('id') + 'panel' );
		var fieldtree = tabpanel.getElementsByTagName('treechildren')[0];

		while (fieldtree.firstChild) fieldtree.removeChild(fieldtree.lastChild);
	}

	for (var relation_alias in rpt_rel_cache) {
		if (!rpt_rel_cache[relation_alias].fields) continue;

		if (selected) {
			if (
				!grep(
					function (x) {
						return x.getAttribute('relation') == relation_alias;
					},
					selected
				).length
			) continue;
		} else {

			$('used-sources-treetop').appendChild(
				createTreeItem(
					{ relation : rpt_rel_cache[relation_alias].alias,
					  idlclass : rpt_rel_cache[relation_alias].idlclass,
					  reltype  : rpt_rel_cache[relation_alias].reltype,
					  path     : rpt_rel_cache[relation_alias].path
					},
					createTreeRow(
						{},
						createTreeCell({ label : rpt_rel_cache[relation_alias].label }),
						createTreeCell({ label : rpt_rel_cache[relation_alias].table }),
						createTreeCell({ label : rpt_rel_cache[relation_alias].alias }),
						createTreeCell({ label : rpt_rel_cache[relation_alias].reltype })
					)
				)
			);
		}

		for each (var tabname in ['filter_tab','aggfilter_tab']) {
			tabpanel = $( tabname + 'panel' );
			fieldtree = tabpanel.getElementsByTagName('treechildren')[0];

			for (var colname in rpt_rel_cache[relation_alias].fields[tabname]) {
				with (rpt_rel_cache[relation_alias].fields[tabname][colname]) {
					fieldtree.appendChild(
						createTreeItem(
							{ relation : relation_alias, datatype : datatype },
							createTreeRow(
								{},
								createTreeCell({ label : alias }),
								createTreeCell({ label : colname }),
								createTreeCell({ label : datatype }),
								createTreeCell({ label : transform_label }),
								createTreeCell({ label : transform })
							)
						)
					);

					fieldtree.lastChild.firstChild.appendChild(
						createTreeCell({ op : op, label : op_label })
					);

					if (op_value.value != undefined) {
						fieldtree.lastChild.firstChild.appendChild(
							createTreeCell({ label : op_value.label })
						);
					}
				}
			}
		}
	}

	tabpanel = $( 'dis_tabpanel' );
	fieldtree = tabpanel.getElementsByTagName('treechildren')[0];
	for each (var order in rpt_rel_cache.order_by) {

		if (selected) {
			if (
				!grep(
					function (x) {
						return x.getAttribute('relation') == order.relation;
					},
					selected
				).length
			) continue;
		}

		with (rpt_rel_cache[order.relation].fields.dis_tab[order.field]) {
			fieldtree.appendChild(
				createTreeItem(
					{ relation : order.relation, datatype : datatype },
					createTreeRow(
						{},
						createTreeCell({ label : alias }),
						createTreeCell({ label : colname }),
						createTreeCell({ label : datatype }),
						createTreeCell({ label : transform_label }),
						createTreeCell({ label : transform })
					)
				)
			);

			fieldtree.lastChild.firstChild.appendChild(
				createTreeCell({ op : op, label : op_label })
			);

			if (op_value.value != undefined) {
				fieldtree.lastChild.firstChild.appendChild(
					createTreeCell({ label : op_value.label })
				);
			}
		}
	}
}

var param_count;
var tab_use = {
	dis_tab       : 'select',
	filter_tab    : 'where',
	aggfilter_tab : 'having',
};


function save_template () {
	param_count = 0;

	var template = {
		version    : 3,
		core_class : $('sources-treetop').getElementsByTagName('treeitem')[0].getAttribute('idlclass'),
		select     : [],
		from       : {},
		where      : [],
		having     : [],
		order_by   : []
	};

	for (var relname in rpt_rel_cache) {
		var relation = rpt_rel_cache[relname];
		if (!relation.fields) continue;

		// first, add the where and having clauses (easier)
		for each (var tab_name in [ 'filter_tab', 'aggfilter_tab' ]) {
			var tab = relation.fields[tab_name];
			for (var field in tab) {
				fleshTemplateField( template, relation, tab_name, field );
			}
		}

		// now the from clause
		fleshFromPath( template, relation );
	}

	// and now for select (based on order_by)
	for each (var order in rpt_rel_cache.order_by)
		fleshTemplateField( template, rpt_rel_cache[order.relation], 'dis_tab', order.field );

	template.rel_cache = rpt_rel_cache;

	//prompt( 'template', js2JSON( template ) );

	// and the saving throw ...
	var cgi = new CGI();
	var session = cgi.param('ses');
	fetchUser( session );

	var tmpl = new rt();
	tmpl.name( $('template-name').value );
	tmpl.description( $('template-description').value );
	tmpl.owner(USER.id());
	tmpl.folder(cgi.param('folder'));
	tmpl.data(js2JSON(template));

	if(!confirm(dojo.string.substitute( rpt_strings.TEMPLATE_CONF_CONFIRM_SAVE, [tmpl.name(), tmpl.description()] )))
		return;

	var req = new Request('open-ils.reporter:open-ils.reporter.template.create', session, tmpl);
	req.request.alertEvent = false;
	req.callback(
		function(r) {
			var res = r.getResultObject();
			if(checkILSEvent(res)) {
				alertILSEvent(res);
			} else {
				if( res && res != '0' ) {
					alert(dojo.string.substitute( rpt_strings.TEMPLATE_CONF_SUCCESS_SAVE, [tmpl.name()] ));
					_l('../oils_rpt.xhtml');
				}
			}
		}
	);

	req.send();
}

function fleshFromPath ( template, rel ) {
	var table_path = rel.path.split( /\./ );
	if (table_path.length > 1 || rel.path.indexOf('-') > -1) table_path.push( rel.idlclass );

	var prev_type = '';
	var prev_link = '';
	var current_path = '';
	var current_obj = template.from;
	var link;
	while (link = table_path.shift()) {

		if (prev_link != '') {
			var prev_class = getIDLClass( prev_link.split(/-/)[0] );
			var prev_field = prev_link.split(/-/)[1];

			var prev_join = prev_field;

			prev_field = prev_field.split(/>/)[0];
			prev_join = prev_join.split(/>/)[1];

			var current_link = getIDLLink( prev_class, prev_field );
			current_obj.key = current_link.getAttribute('key');

            //console.log("prev_link in fleshFromPath is: " + prev_link);
            //console.log("prev_join in fleshFromPath is: " + prev_join);

            if (prev_join) current_obj.type = prev_join
			else if ( 
				(
					current_link.getAttribute('reltype') != 'has_a' ||
					prev_type == 'left' ||
					rel.reltype != 'has_a'

// This disallows outer joins when the item is used in a filter
//				) && (
//					getKeys(rel.fields.filter_tab).length == 0 &&
//					getKeys(rel.fields.aggfitler_tab).length == 0

				)
			) current_obj.type = 'left';

			prev_type = current_obj.type; 

		}

		if (current_path) current_path += '-';
		current_path += link.split(/>/)[0];

		var leaf = table_path.length == 0 ? true : false;

		current_obj.path = current_path;
		current_obj.table = getSourceDefinition( link.split(/-/)[0] );


		if (leaf) {

    		var join_type = link.split(/-/)[1];
            if (join_type) {
	        	join_type = join_type.split(/>/)[1];
			    if (join_type && join_type != 'undefined') current_obj.type = join_type;
            }

			current_obj.label = rel.label;
			current_obj.alias = rel.alias;
			current_obj.idlclass = rel.idlclass;
			current_obj.template_path = rel.path;
		} else {
			var current_class = getIDLClass( link.split(/-/)[0] );
			var join_field = link.split(/-/)[1];
			var join_type = join_field;

			join_field = join_field.split(/>/)[0];
			join_type = join_type.split(/>/)[1];

            //console.log("join_field in fleshFromPath is: " + join_field);

			var join_link = getIDLLink(current_class, join_field);

			if (join_link.getAttribute('reltype') != 'has_a') {
				var fields_el = current_class.getElementsByTagName('fields')[0];
				join_field =
					fields_el.getAttributeNS(persistNS, 'primary') +
					'-' + join_link.getAttribute('class') +
					'-' + join_link.getAttribute('key');
			}

			if (!current_obj.alias) current_obj.alias = hex_md5( current_path ) ;
			join_field += '-' + current_obj.alias;

			if (!current_obj.join) current_obj.join = {};
			if (!current_obj.join[join_field]) current_obj.join[join_field] = {};

			if (current_obj.type == 'left') current_obj.join[join_field].type = 'left';

			current_obj = current_obj.join[join_field];
		}

		prev_link = link;
	}


}

function fleshTemplateField ( template, rel, tab_name, field ) {

	if (!rel.fields[tab_name] || !rel.fields[tab_name][field]) return;

	var tab = rel.fields[tab_name];

	var table_path = rel.path.split( /\./ );
	if (table_path.length > 1 || rel.path.indexOf('-') > -1)
		table_path.push( rel.idlclass );

	table_path.push( field );

	var field_path = table_path.join('-');

	var element = {
		alias : tab[field].alias,
		column :
		  	{ colname : field,
			  transform : tab[field].transform,
			  transform_label : tab[field].transform_label
			},
		path : field_path,
		relation : rel.alias
	};

	if (tab_name.match(/filter/)) {
		element.condition = {};
		if (tab[field].op == 'is' || tab[field].op == 'is not' || tab[field].op == 'is blank' || tab[field].op == 'is not blank') {
			element.condition[tab[field].op] = null;
		} else {
			element.condition[tab[field].op] =
				tab[field].op_value.value ?
					tab[field].op_value.value :
					'::P' + param_count++;
		}
	}

	template[tab_use[tab_name]].push(element);
}

