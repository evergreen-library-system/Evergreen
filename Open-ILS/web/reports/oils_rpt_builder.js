/** initializes reports, some basid display settings, 
  * grabs and builds the IDL tree
  */
dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");
var __dblclicks = {}; /* retain a cache of the selector value doubleclick event handlers */

function oilsInitReportBuilder() {
	if(!oilsInitReports()) return false;
	oilsReportBuilderReset();
	DOM.oils_rpt_table.onclick = 
		function(){hideMe(DOM.oils_rpt_column_editor)};
	oilsDrawRptTree(
		function() { 
			hideMe(DOM.oils_rpt_tree_loading); 
			unHideMe(DOM.oils_rpt_table); 
			oilsRptBuilderDrawClone(new CGI().param('ct'));
		}
	);

	DOM.oils_rpt_builder_save_template.onclick = oilsReportBuilderSave;
}

function oilsRptBuilderDrawClone(templateId) {
	if(!templateId) return;
	unHideMe(DOM.oils_rpt_builder_cloning);

	oilsRptFetchTemplate(templateId,
		function(template) { oilsRptBuilderDrawClone2(template);}
	);
}


function oilsRptBuilderDrawClone2(template) {
	appendClear( DOM.oils_rpt_build_cloning_name, template.name() );
	DOM.oils_rpt_builder_new_name.value = template.name();
	DOM.oils_rpt_builder_new_desc.value = template.description();

	_debug(formatJSON(template.data()));

	/* manually shove data into the display selectors */
	var def = JSON2js(template.data());

   /* --------------------------------------------------------------- */
   /* hack to determine the higest existing param in the template */
   matches = template.data().match(/::P\d/g);
   var max = 0;
   for( var i = 0; i < matches.length; i++ ) {
      var num = parseInt(matches[i].replace(/::P(\d)/,'$1')); 
      if( num > max ) max = num;
   }
   oilsRptID2 = max + 1;
   _debug("set next avail param to " + oilsRptID2);
   //_debug('PARAM = ' + oilsRptNextParam());
   //var x = null;
   //x.blah();
   /* --------------------------------------------------------------- */

	var table = def.from.table;
	var node;
	for( var i in oilsIDL ) {
		node = oilsIDL[i];
		if( node.table == table ) {
			setSelector(DOM.oils_rpt_builder_type_selector, node.name);
			DOM.oils_rpt_builder_type_selector.onchange();
			break;
		}
	}

	iterate(def.select,
		function(item) {
			oilsAddRptDisplayItem(item.path, item.alias, item.column.transform)});

	iterate(def.where,
		function(item) {
			oilsAddRptFilterItem(item.path, item.column.transform, oilsRptObjectKeys(item.condition)[0])});

	iterate(def.having,
		function(item) {
			oilsAddRptHavingItem(item.path, item.column.transform, oilsRptObjectKeys(item.condition)[0])});

	//oilsRpt.setTemplate(template); /* commented out with clone fix, *shouldn't* break anything */
	oilsRpt.templateObject = null; /* simplify debugging */
}

function oilsReportBuilderReset() {
	var n = (oilsRpt) ? oilsRpt.name : "";
	oilsRpt = new oilsReport();
	oilsRpt.name = n;
	oilsRptDisplaySelector	= DOM.oils_rpt_display_selector;
	oilsRptFilterSelector	= DOM.oils_rpt_filter_selector;
	oilsRptHavingSelector	= DOM.oils_rpt_agg_filter_selector;
	removeChildren(oilsRptDisplaySelector);
	removeChildren(oilsRptFilterSelector);
	removeChildren(oilsRptHavingSelector);
	//removeChildren(oilsRptOrderBySelector);
	//oilsRptResetParams();
}

function oilsReportBuilderSave() {

	var tmpl = new rt();
	tmpl.name(DOM.oils_rpt_builder_new_name.value);
	tmpl.description(DOM.oils_rpt_builder_new_desc.value);
	tmpl.owner(USER.id());
	tmpl.folder(new CGI().param('folder'));
	tmpl.data(js2JSON(oilsRpt.def));

	if(!confirm(dojo.string.substitute( rpt_strings.RPT_BUILDER_CONFIRM_SAVE, [tmpl.name(), tmpl.description()] )) )
		return;

	debugFMObject(tmpl);
	//return; /* XXX */

	var req = new Request(OILS_RPT_CREATE_TEMPLATE, SESSION, tmpl);
	req.request.alertEvent = false;
	req.callback(
		function(r) {
			var res = r.getResultObject();
			if(checkILSEvent(res)) {
				alertILSEvent(res);
			} else {
				if( res && res != '0' ) {
					oilsRptAlertSuccess();
					_l('oils_rpt.xhtml');
				} 
			}
		}
	);
	
	req.send();
}



/* adds an item to the display window */
function oilsAddRptDisplayItem(path, name, tform, params) {

	if( ! oilsAddSelectorItem( 
		{  selector : oilsRptDisplaySelector, 
			val : path, 
			label : name, 
			path : path, 
			type : 'display',
			transform : tform }) ) {
		return;
	}

	/* add the selected columns to the report output */
	name = (name) ? name : oilsRptPathCol(path);
	if( !tform ) tform = 'Bare';

	var aggregate = oilsRptGetIsAgg(tform);

	/* add this item to the select blob */
	var sel = {
		relation: hex_md5(oilsRptPathRel(path)), 
		path : path,
		alias: name,
		column: { transform: tform, colname: oilsRptPathCol(path) }
	};

	if( params ) sel.column.params = params;
	oilsRptAddSelectList(sel, tform);
	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRptDebug();
}

function oilsRptAddSelectList(obj, tform) {
	if(!oilsRptGetIsAgg(tform)) {
		var select = [];
		var added = false;
		for( var i = 0; i < oilsRpt.def.select.length; i++ ) {
			var item = oilsRpt.def.select[i];

			/* shove the item in question in front of the first agg tform */
			if( !added && oilsRptGetIsAgg( item.column.transform ) ) {
				select.push(obj);
				added = true;
			}
			select.push(item);
		}

		/* if there is no existing agg tfrom to 
			insert in front of, add me on the end */
		if(!added) select.push(obj);

		oilsRpt.def.select = select;

		if( added ) {
			/* re-draw the select display to get the order correct */
			var sel = oilsRptDisplaySelector;
			while( sel.options.length > 0 ) sel.options[0] = null;
			iterate(oilsRpt.def.select,
				function(item) {
					_debug('re-inserting display item ' + item.path);
					oilsAddSelectorItem(
						{  selector: oilsRptDisplaySelector, 
							val:item.path, 
							label:item.alias, 
							path:item.path,
							transform : item.column.transform,
							type : 'display'
						}
					) });
		}

	} else {
		/* shove agg transforms onto the end */
		oilsRpt.def.select.push(obj);
	}
}



function oilsRptGetIsAgg(tform) {
	return OILS_RPT_TRANSFORMS[tform].aggregate;
}

/* takes a column path and builds a from-clause object for the path */
function oilsRptBuildFromClause(path) {

	/* the path is the full path (relation) from the source 
		object to the column in question (e.g. au-home_ou-aou-name)*/
	var parts = path.split(/-/);

	/* the final from clause */
	var obj = {}; 

	/* reference to the current position in the from clause */
	var tobj = obj; 

	var newpath = "";

   var last_is_left = false; /* true if our parent join is a 'left' join */

	/* walk the path, fleshing the from clause as we go */
	for( var i = 0; i < parts.length; i += 2 ) {

		var cls = parts[i]; /* class name (id) */
		var col = parts[i+1]; /* column name */

		/* a "node" is a class description from the IDL, it 
			contains relevant info, plus a list of "fields",
			or column objects */
		var node = oilsIDL[cls];
		var pkey = oilsRptFindField(node, node.pkey);

		/* a "field" is a parsed version of a column from the IDL,
			contains datatype, column name, etc. */
		var field = oilsRptFindField(node, col);

		/* re-construct the path as we go so 
			we know what all we've seen thus far */
		newpath = (newpath) ? newpath + '-'+ cls : cls;

		/* extract relevant info */
		tobj.table = node.table;
		tobj.path = newpath;
		tobj.alias = hex_md5(newpath);

		_debug('field type is ' + field.type);
		if( i == (parts.length - 2) ) break;

		/* we still have columns left in the path, keep adding join's */
		var path_col = col;
		if(field.reltype != 'has_a')
			col = pkey.name + '-' + col;

		tobj.join = {};
		tobj = tobj.join;

		tobj[col] = {};
		tobj = tobj[col];
		if( field.type == 'link' ) {
			tobj.key = field.key;
			if( field.reltype == 'has_many' || field.reltype == 'might_have' || last_is_left ) {
				tobj.type = 'left';
            last_is_left = true;
         } else {
            last_is_left = false;
         }
		}

		newpath = newpath + '-'+ path_col;
	}

	_debug("built 'from' clause: path="+path+"\n"+formatJSON(js2JSON(obj)));
	return obj;
}

function oilsMoveUpDisplayItems() {
	var sel = oilsRptDisplaySelector;
	var idx = sel.selectedIndex;
	if( idx == 0 ) return;
	var opt = sel.options[idx];
	sel.options[idx] = null;
	idx--;

	var val = opt.getAttribute('value');
   var label = opt.getAttribute('label');
   var path = opt.getAttribute('path');
   var evt_id = opt.getAttribute('listener');

	opt = insertSelectorVal(sel, idx, label, val);

	opt.setAttribute('path', path);
	opt.setAttribute('title', label);
   opt.setAttribute('label', label);
   opt.setAttribute('value', val);
   opt.setAttribute('listener', evt_id);

   /* re-attach the double-click event */
	opt.addEventListener('dblclick', __dblclicks[evt_id], true );

	sel.options[idx].selected = true;

	var arr = oilsRpt.def.select;
	for( var i = 0; i < arr.length; i++ ) {
		if( arr[i].path == val ) {
			var other = arr[i-1];
			arr[i-1] = arr[i];
			arr[i] = other;
			break;
		}
	}
	oilsRptDebug();
}

function oilsMoveDownDisplayItems() {
	var sel = oilsRptDisplaySelector;
	var idx = sel.selectedIndex;
	if( idx == sel.options.length - 1 ) return;
	var opt = sel.options[idx];
	sel.options[idx] = null;
	idx++;

	//var val = opt.getAttribute('value');
	//insertSelectorVal(sel, idx, opt.innerHTML, val);
	//insertSelectorVal(sel, idx, opt.getAttribute('label'), val);

	var val = opt.getAttribute('value');
   var label = opt.getAttribute('label');
   var path = opt.getAttribute('path');
   var evt_id = opt.getAttribute('listener');

	opt = insertSelectorVal(sel, idx, label, val);

   opt.setAttribute('value', val);
	opt.setAttribute('path', path);
	opt.setAttribute('title', label);
   opt.setAttribute('label', label);
   opt.setAttribute('listener', evt_id);

   /* re-attach the double-click event */
	opt.addEventListener('dblclick', __dblclicks[evt_id], true );

	sel.options[idx].selected = true;

	var arr = oilsRpt.def.select;
	for( var i = 0; i < arr.length; i++ ) {
		if( arr[i].path == val ) {
			var other = arr[i+1];
			arr[i+1] = arr[i];
			arr[i] = other;
			break;
		}
	}
	oilsRptDebug();
}


/* removes a specific item from the display window */
/*
function oilsDelDisplayItem(val) {
	oilsDelSelectorItem(oilsRptDisplaySelector, val);
}
*/

/* removes selected items from the display window */
function oilsDelSelectedDisplayItems() {
	var list = oilsDelSelectedItems(oilsRptDisplaySelector);

	_debug('deleting list: ' + list);

	/* remove the de-selected columns from the report output */
	oilsRpt.def.select = grep( oilsRpt.def.select, 
		function(i) {
			for( var j = 0; j < list.length; j++ ) {
				var d = list[j]; /* path */
				var col = i.column;

				_debug('in delete, looking at list = '+d+' : col = ' + 
					col.colname + ' : relation = ' + i.relation + ' : encoded = ' + hex_md5(oilsRptPathRel(d)) );

				if( hex_md5(oilsRptPathRel(d)) == i.relation && oilsRptPathCol(d) == col.colname ) {
					return false;
				}
			}
			return true;
		}
	);

	if(!oilsRpt.def.select) oilsRpt.def.select = [];
	oilsRptPruneFromList(list);
	oilsRptDebug();
}

function oilsRptPruneFromList(pathlist) {

	for( var j = 0; j < pathlist.length; j++ ) {
		/* if there are no items left in the "select", "where", or "having" clauses 
			for the given relation, trim this relation from the "from" clause */
		var path = pathlist[j];
		var encrel = hex_md5(oilsRptPathRel(path));

		debug('seeing if we can prune from clause with relation = ' + encrel +' : path = ' + path);

		var func = function(i){ return (i.relation == hex_md5(oilsRptPathRel(path))); };

		if(	!grep(oilsRpt.def.select, func) && 
				!grep(oilsRpt.def.where, func) && 
				!grep(oilsRpt.def.having, func) ) {

			debug('looks like we can prune ' + path);

			oilsRptPruneFromClause(oilsRptPathRel(pathlist[j]));
		}
	}
}


/* for each item in the path list, remove the associated data
	from the "from" clause */

function oilsRptPruneFromClause(relation, node) {

	var keys = oilsRptObjectKeys(node);
	_debug("trying to remove relation: " + relation+'\n\tthis object has keys: '+keys);

	if(!node) node = oilsRpt.def.from.join;
	if(!node) return false;

	for( var i in node ) {
		var child_node = node[i];
		_debug("\tanalyzing child node: "+child_node.path);

		// first, descend into the tree, and prune leaves 
		if( child_node.join ) {

			oilsRptPruneFromClause(relation, child_node.join); 
			var join_keys = oilsRptObjectKeys(child_node.join);
			_debug("\tchild has a sub-join for items : ["+ join_keys+"]");

			if(join_keys.length == 0) {
				_debug("\tdeleting join for object "+i);
				delete child_node.join;
			}
		}

		if( !child_node.join ) {

			_debug("\tchild node has no sub-join, seeing if we should delete it");

			var from_alias = child_node.alias;
			var func = function(n){ return (n.relation == from_alias)};
	
			if(	!grep(oilsRpt.def.select, func) &&
					!grep(oilsRpt.def.where, func) &&
					!grep(oilsRpt.def.having, func) ) {
	
				/* we are not used by any other clauses */
				_debug("\tdeleting node with relation: "+ from_alias);
				delete node[i];
				return true;
			}
		}
	}

	return false;
}

function oilsRptMkFilterTags(path, tform, filter) {
	var name = oilsRptMakeLabel(path);
	if(tform) name += ' ('+tform+')';
	name += ' "' + filter + '"';
	var epath = path + ':'+filter+':';
	if(tform) epath += tform;

	return [ name, epath ];
}


function oilsAddRptFilterItem(path, tform, filter) {
	_debug("Adding filter item for "+path+" tform="+tform+" filter="+filter);

	var name = oilsRptMkFilterTags(path, tform, filter);
	var epath = name[1];
	name = name[0];

	if( ! oilsAddSelectorItem(
		{  selector : oilsRptFilterSelector, 
			val : epath, 
			label : name, 
			path : path,
			transform : tform,
			operation : filter,
			type : 'filter'
		}) )
		return;

	var where = {
		relation: hex_md5(oilsRptPathRel(path)), 
		path : path,
		column:   { transform: tform, colname: oilsRptPathCol(path) },
		condition : {}
	};

   //_debug('NEXT PARAM = ' + oilsRptID2);
   //_debug('NEXT PARAM = ' + oilsRptNextParam());

	if( filter == 'is' || filter == 'is not' || filter == 'is blank' || filter == 'is not blank' )
		where.condition[filter] = null;
	else where.condition[filter] = oilsRptNextParam();

	switch(tform) {
		case 'substring' : where.column.params = oilsRptNextParam();
	}

	oilsRpt.def.where.push(where);
	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRptDebug();
}


function oilsAddRptHavingItem(path, tform, filter) {
	_debug("Adding filter item for "+path+" tform="+tform+" filter="+filter);

	var name = oilsRptMkFilterTags(path, tform, filter);
	var epath = name[1];
	name = name[0];

	if( ! oilsAddSelectorItem(
		{  selector: oilsRptHavingSelector, 
			val:epath, 
			label:name, 
			path:path,
			transform : tform,
			operation : filter,
			type : 'agg_filter' /* XXX */
		}) )

		return;

	var having = {
		relation: hex_md5(oilsRptPathRel(path)), 
		path : path,
		column:   { transform: tform, colname: oilsRptPathCol(path) },
		condition : {}
	};
	if( filter == 'is' || filter == 'is not' || filter == 'is blank' || filter == 'is not blank' )
		having.condition[filter] = null;
	else having.condition[filter] = oilsRptNextParam();

	switch(tform) {
		case 'substring' : having.column.params = oilsRptNextParam();
	}

	oilsRpt.def.having.push(having);
	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRptDebug();
}



function oilsDelSelectedFilterItems() {
	_oilsDelSelectedFilterItems('where');
}
function oilsDelSelectedAggFilterItems() {
	_oilsDelSelectedFilterItems('having');
}

function _oilsDelSelectedFilterItems(type) {

	/* the values in this list are formed:  <path>:<operation>:<transform> */
	var list;
    if( type == 'where' )
	    list = oilsDelSelectedItems(oilsRptFilterSelector);
    else if( type == 'having' )
	    list = oilsDelSelectedItems(oilsRptHavingSelector);

	_debug("deleting filter items " + list);

	for( var i = 0; i < list.length; i++ ) {
		var enc_path = list[i];
		var data = oilsRptParseFilterEncPath(enc_path);

		_debug("trimming filter items with enc_path = " + enc_path);
		_debug(data.path);
		_debug(data.operation);
		_debug(data.tform);
		_debug(data.tform);
		_debug(type);
		_debug('---------------------');

		oilsRpt.def[type] = grep( 
			oilsRpt.def[type],
			function(f) { 
				return ! oilsRptFilterDataMatches( 
					f, data.path, data.operation, data.tform );
			}
		);
	}

	if(!oilsRpt.def[type]) oilsRpt.def[type] = [];
	oilsRptPruneFromList(list);
	oilsRptDebug();
}

function oilsRptParseFilterEncPath(item) {
	return {
		path:		item.replace(/:.*/,''),
		operation:	item.replace(/.*:(.*):.*/,'$1'),
		tform:	item.replace(/.*?:.*?:(.*)/,'$1')
	};
}


function oilsRptFilterDataMatches(filter, path, operation, tform) {
	var rel = hex_md5(oilsRptPathRel(path));
	var col = oilsRptPathCol(path);

	if(	col == filter.column.colname &&
			rel == filter.relation &&	
			tform == filter.column.transform &&
			operation == oilsRptObjectKeys(filter.condition)[0] ) return true;

	return false;
}

/* adds an item to the display window */
/*
function oilsAddRptAggFilterItem(val) {
	oilsAddSelectorItem({selector:oilsRptHavingFilterSelector, val:val, label:val, path:val});
}
*/

/* removes a specific item from the display window */
/*
function oilsDelAggFilterItem(val) {
	oilsDelSelectorItem(oilsRptHavingFilterSelector, val);
}
*/


/* adds an item to the display window */
//function oilsAddSelectorItem(sel, val, name, path) {
function oilsAddSelectorItem(args) {

	var sel = args.selector;
	var label = args.label;
	var path = args.path;
	var val = args.val;

	label = (label) ? label : oilsRptMakeLabel(val);

	var i;
	for( i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		if( opt.value == val ) return false;
	}

	var opt = insertSelectorVal( sel, -1, label, val );
	opt.setAttribute('title', label);
	opt.setAttribute('path', path);
   opt.setAttribute('label', label);

   var evt_id = oilsNextNumericId();
   opt.setAttribute('listener', evt_id);

	args.index = i;
	delete args.selector;
   var listener = function(){ oilsRptDrawDataWindow(path, args);};
	opt.addEventListener('dblclick', listener, true );
   __dblclicks[evt_id] = listener;
		//function(){ oilsRptDrawDataWindow(path, args);} , true);

	return true;
}


/* removes a specific item from the display window */
function oilsDelSelectorItem(sel, val) {
	var opts = sel.options;
	for( var i = 0; i < opts.length; i++ ) {
		var opt = opts[i];
		if( opt.value == val )  {
			if( i == opts.length - 1 ) 
				opts[i] = null;
			else opts[i] = opts[i+1];
			return;
		}
	}
}

/* removes selected items from the display window */
function oilsDelSelectedItems(sel) {
	var list = getSelectedList(sel);
	for( var i = 0; i < list.length; i++ ) 
		oilsDelSelectorItem(sel, list[i]);
	return list;
}


/* hides the different field editor tabs */
function oilsRptHideEditorDivs() {
	hideMe(DOM.oils_rpt_tform_div);
	hideMe(DOM.oils_rpt_filter_div);
	hideMe(DOM.oils_rpt_agg_filter_div);
	hideMe(DOM.oils_rpt_order_by_div);

	removeCSSClass(DOM.oils_rpt_tform_tab.parentNode, 'oils_rpt_tab_picker_selected');
	removeCSSClass(DOM.oils_rpt_filter_tab.parentNode, 'oils_rpt_tab_picker_selected');
	removeCSSClass(DOM.oils_rpt_agg_filter_tab.parentNode, 'oils_rpt_tab_picker_selected');
}


/**
  This draws the 3-tabbed window containing the transform,
  filter, and aggregate filter picker window
  */
function oilsRptDrawDataWindow(path, args) {

	args = (args) ? args : {};

	for( var x in args ) 
		_debug("oilsRptDrawDataWindow(): args -> " + x + " = " + args[x]);

	var col	= oilsRptPathCol(path);
	var cls	= oilsRptPathClass(path);
	var field = oilsRptFindField(oilsIDL[cls], col);

	appendClear(DOM.oils_rpt_editor_window_label, text(oilsRptMakeLabel(path)));
	appendClear(DOM.oils_rpt_editor_window_datatype, text(field.datatype));

	_debug("setting update data window for column "+col+' on class '+cls);

	var div = DOM.oils_rpt_column_editor;
	/* set a preliminary top position so the page won't bounce around */


	/* XXX */
	//div.setAttribute('style','top:'+oilsMouseX+'px');

	/* unhide the div so we can determine the dimensions */
	unHideMe(div);

	/* don't let them see the floating div until the position is fully determined */
	div.style.visibility='hidden'; 

	oilsRptDrawTransformWindow(path, col, cls, field, args);
	oilsRptDrawFilterWindow(path, col, cls, field, args);
	oilsRptDrawHavingWindow(path, col, cls, field, args);
	//oilsRptDrawOrderByWindow(path, col, cls, field);

	//buildFloatingDiv(div, 600);

	//window.scrollTo(0,0);
	window.scrollTo(0, 60);

	/* now let them see it */
	div.style.visibility='visible';
	//args.type = (args.type) ? args.type : 'display';
	oilsRptSetDataWindowActions(div, args);
}


function oilsRptSetDataWindowActions(div, args) {
	/* give the tab links behavior */

	DOM.oils_rpt_tform_tab.onclick = 
		function(){
			oilsRptHideEditorDivs();
			unHideMe(DOM.oils_rpt_tform_div)
			addCSSClass(DOM.oils_rpt_tform_tab.parentNode, 'oils_rpt_tab_picker_selected');
		};

	DOM.oils_rpt_filter_tab.onclick = 
		function(){
			oilsRptHideEditorDivs();
			unHideMe(DOM.oils_rpt_filter_div)
			addCSSClass(DOM.oils_rpt_filter_tab.parentNode, 'oils_rpt_tab_picker_selected');
		};

	DOM.oils_rpt_agg_filter_tab.onclick = 
		function(){
			oilsRptHideEditorDivs();
			unHideMe(DOM.oils_rpt_agg_filter_div)
			addCSSClass(DOM.oils_rpt_agg_filter_tab.parentNode, 'oils_rpt_tab_picker_selected');
		};

	/*
	DOM.oils_rpt_order_by_tab.onclick = 
		function(){
			oilsRptHideEditorDivs();
			oilsRptDrawOrderByWindow();
			unHideMe(DOM.oils_rpt_order_by_div);
			};
			*/

	DOM.oils_rpt_tform_submit.disabled = false;
	DOM.oils_rpt_filter_submit.disabled = false;
	DOM.oils_rpt_agg_filter_submit.disabled = false;

	if( !args.type ) {
		DOM.oils_rpt_tform_tab.onclick();
	} else {
		/* disable editing on existing items for now */
		if( args.type == 'display' ) {
			DOM.oils_rpt_tform_tab.onclick();
			DOM.oils_rpt_tform_submit.disabled = true;
		}
		if( args.type == 'filter' ) {
			DOM.oils_rpt_filter_tab.onclick();
			DOM.oils_rpt_filter_submit.disabled = true;
		}
		if( args.type == 'agg_filter' ) {
			DOM.oils_rpt_agg_filter_tab.onclick();
			DOM.oils_rpt_agg_filter_submit.disabled = true;
		}
	}

	DOM.oils_rpt_column_editor_close_button.onclick = function(){hideMe(div);};
}


function oilsRptDrawFilterWindow(path, col, cls, field, args) {

	var tformPicker = new oilsRptTformPicker( {	
			node : DOM.oils_rpt_filter_tform_table,
			datatype : field.datatype,
			non_aggregate : true,
			select : args.transform
		}
	);

	var filterPicker = new oilsRptFilterPicker({
			node : DOM.oils_rpt_filter_op_table,
			datatype : field.datatype,
			select : args.operation
		}
	);

	DOM.oils_rpt_filter_submit.onclick = function() {
		oilsAddRptFilterItem(
			path, tformPicker.getSelected(), filterPicker.getSelected());
	}
}


function oilsRptDrawHavingWindow(path, col, cls, field, args) {
	var tformPicker = new oilsRptTformPicker( {	
			node : DOM.oils_rpt_agg_filter_tform_table,
			datatype : field.datatype,
			aggregate : true,
			select : args.transform
		}
	);

	var filterPicker = new oilsRptFilterPicker({
			node : DOM.oils_rpt_agg_filter_op_table,
			datatype : field.datatype,
			select : args.operation
		}
	);

	DOM.oils_rpt_agg_filter_submit.onclick = function() {
		oilsAddRptHavingItem(
			path, tformPicker.getSelected(), filterPicker.getSelected());
	}
}

/* draws the transform window */
function oilsRptDrawTransformWindow(path, col, cls, field, args) {
	args = (args) ? args : {};

	DOM.oils_rpt_tform_label_input.value = 
		(args.label) ? args.label : oilsRptMakeLabel(path);

	var dtype = field.datatype;

	var tformPicker = new oilsRptTformPicker( {	
			node : DOM.oils_rpt_tform_table,
			datatype : field.datatype,
			non_aggregate : true,
			aggregate : true,
			select : args.transform
		}
	);

	DOM.oils_rpt_tform_submit.onclick = 
		function(){ 
			oilsAddRptDisplayItem(path, 
				DOM.oils_rpt_tform_label_input.value, tformPicker.getSelected() );
		};

	DOM.oils_rpt_tform_label_input.focus();
	DOM.oils_rpt_tform_label_input.select();

	_debug("Building transform window for datatype "+dtype);
}


//function oilsRptDrawOrderByWindow(path, col, cls, field) {
function oilsRptDrawOrderByWindow() {
	var sel = DOM.oils_rpt_order_by_selector;
	removeChildren(sel);
	DOM.oils_rpt_order_by_submit.onclick = function() {
		oilsRptAddOrderBy(getSelectorVal(sel));
	}

	var cols = oilsRpt.def.select;
	for( var i = 0; i < cols.length; i++ ) {
		var obj = cols[i];
		insertSelectorVal(sel, -1, obj.alias, obj.path);
	}
}

function oilsRptAddOrderBy(path) {
	var rel = hex_md5(oilsRptPathRel(path));
	var order_by = oilsRpt.def.order_by;

	/* if this item is already in the order by remove it and overwrite it */
	order_by = grep(oilsRpt.def.order_by, 
		function(i) {return (i.path != path)});
	
	if(!order_by) order_by = [];

	/* find the column definition in the select blob */
	var obj = grep(oilsRpt.def.select,
		function(i) {return (i.path == path)});
	
	if(!obj) return;
	obj = obj[0];
	
	order_by.push({ 
		relation : obj.relation, 
		column : obj.column,
		direction : getSelectorVal(DOM.oils_rpt_order_by_dir)
	});

	oilsRpt.def.order_by = order_by;
	oilsRptDebug();
}



