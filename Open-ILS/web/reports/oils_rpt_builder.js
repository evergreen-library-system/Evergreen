/** initializes reports, some basid display settings, 
  * grabs and builds the IDL tree
  */
function oilsInitReportBuilder() {
	if(!oilsInitReports()) return false;
	oilsReportBuilderReset();
	DOM.oils_rpt_table.onclick = 
		function(){hideMe(DOM.oils_rpt_column_editor)};
	oilsDrawRptTree(
		function() { 
			hideMe(DOM.oils_rpt_tree_loading); 
			unHideMe(DOM.oils_rpt_table); 
		}
	);

	DOM.oils_rpt_builder_save_template.onclick = oilsReportBuilderSave;
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
	oilsRptResetParams();
}

function oilsReportBuilderSave() {

	var tmpl = new rt();
	tmpl.name(DOM.oils_rpt_builder_new_name.value);
	tmpl.description(DOM.oils_rpt_builder_new_desc.value);
	tmpl.owner(USER.id());
	tmpl.folder(new CGI().param('folder'));
	tmpl.data(js2JSON(oilsRpt.def));

	if(!confirm('Name : '+tmpl.name() + '\nDescription: ' + tmpl.description()+'\nSave Template?'))
		return;

	debugFMObject(tmpl);
	//return; /* XXX */

	var req = new Request(OILS_RPT_CREATE_TEMPLATE, SESSION, tmpl);
	req.callback(
		function(r) {
			var res = r.getResultObject();
			if( res && res != '0' ) {
				oilsRptAlertSuccess();
				_l('oils_rpt.xhtml');
			} 
		}
	);
	
	req.send();
}



/* adds an item to the display window */
function oilsAddRptDisplayItem(path, name, tform, params) {
	if( ! oilsAddSelectorItem(oilsRptDisplaySelector, path, name) ) 
		return;

	/* add the selected columns to the report output */
	name = (name) ? name : oilsRptPathCol(path);
	if( !tform ) tform = 'Bare';

	var aggregate = oilsRptGetIsAgg(tform);

	/* add this item to the select blob */
	var sel = {
		relation: hex_md5(oilsRptPathRel(path)), 
		path : path,
		alias:    name,
		column:   { transform: tform, colname: oilsRptPathCol(path) }
	};

	if( params ) sel.column.params = params;

	if(!oilsRptGetIsAgg(tform)) {
		var select = [];
		var added = false;
		for( var i = 0; i < oilsRpt.def.select.length; i++ ) {
			var item = oilsRpt.def.select[i];
			if( !added && oilsRptGetIsAgg( item.column.transform ) ) {
				select.push(sel);
				added = true;
			}
			select.push(item);
		}
		if(!added) select.push(sel);
		oilsRpt.def.select = select;
	} else {
		oilsRpt.def.select.push(sel);
	}


	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRptDebug();
}

function oilsRptGetIsAgg(tform) {
	return OILS_RPT_TRANSFORMS[tform].aggregate;
	
	/* DEPRECATED */
	var sel = $n(DOM.oils_rpt_tform_table,'selector');
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		if( opt.getAttribute('value') == tform )
			return opt.getAttribute('aggregate');
	}
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
		if( field.type == 'link' )
			tobj.key = field.key;

		newpath = newpath + '-'+ path_col;
	}

	_debug("built 'from' clause: path="+path+"\n"+formatJSON(js2JSON(obj)));
	return obj;
}


/* removes a specific item from the display window */
function oilsDelDisplayItem(val) {
	oilsDelSelectorItem(oilsRptDisplaySelector, val);
}

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

	/*
	for( var j = 0; j < list.length; j++ ) {
		debug('seeing if we can prune from clause with relation = ' + hex_md5(oilsRptPathRel(list[j])));
		if(	!grep(oilsRpt.def.select,
				function(i){ return (i.relation == hex_md5(oilsRptPathRel(list[j]))); })
			&& !grep(oilsRpt.def.where,
				function(i){ return (i.relation == hex_md5(oilsRptPathRel(list[j]))); })
			&& !grep(oilsRpt.def.having,
				function(i){ return (i.relation == hex_md5(oilsRptPathRel(list[j]))); })
		) {
			_debug('pruning from clause');
			oilsRptPruneFromClause(oilsRptPathRel(list[j]));
		}
	}
	*/

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

			oilsRptPruneFromClause(oilsRptPathRel(pathlist[j]));
		}
	}
}


/* for each item in the path list, remove the associated data
	from the "from" clause */

function oilsRptPruneFromClause(relation, node) {
	_debug("removing relation from 'from' clause: " + relation);
	if(!node) node = oilsRpt.def.from.join;
	if(!node) return false;

	for( var i in node ) {
		_debug("from prune looking at node "+node[i].path);
		// first, descend into the tree, and prune leaves first
		if( node[i].join ) {
			oilsRptPruneFromClause(relation, node[i].join); 
			if(oilsRptObjectKeys(node[i].join).length == 0) 
				delete node[i].join;
		}
	}

	if(!node.join) {

		var key = oilsRptObjectKeys(node)[0];
		var from_alias = node[key].alias;
		var func = function(n){ return (n.relation == from_alias)};

		_debug("pruning from clause with alias "+ from_alias);

		if(	!grep(oilsRpt.def.select, func) &&
				!grep(oilsRpt.def.where, func) &&
				!grep(oilsRpt.def.having, func) ) {

			// if we're at an unused empty leaf, remove it
			delete node[i];
			return true;
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

	if( ! oilsAddSelectorItem(oilsRptFilterSelector, epath, name) )
		return;

	var where = {
		relation: hex_md5(oilsRptPathRel(path)), 
		path : path,
		column:   { transform: tform, colname: oilsRptPathCol(path) },
		condition : {}
	};
	if( filter == 'is' || filter == 'is not' )
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

	if( ! oilsAddSelectorItem(oilsRptHavingSelector, epath, name) )
		return;

	var having = {
		relation: hex_md5(oilsRptPathRel(path)), 
		path : path,
		column:   { transform: tform, colname: oilsRptPathCol(path) },
		condition : {}
	};
	if( filter == 'is' || filter == 'is not' )
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
	var list = oilsDelSelectedItems(oilsRptFilterSelector);

	for( var i = 0; i < list.length; i++ ) {
		var enc_path = list[i];
		var data = oilsRptParseFilterEncPath(enc_path);
		oilsRpt.def[type] = grep( 
			oilsRpt.def[type],
			function(f) { 
				return oilsRptFilterDataMatches( 
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
			operation == oilsRptObjectKeys(filter)[0] ) return true;

	return false;
}

/*
function oilsRptFilterGrep(flist, filter) {

	for( var j = 0; j < flist.length; j++ ) {

		var fil	= flist[j];
		var col	= filter.column;
		var frel = hex_md5(oilsRptPathRel(fil.path));
		var fcol = oilsRptPathCol(fil.path);

		var op = oilsRptObjectKeys(filter.condition)[0];

		if(	frel == filter.relation && 
				fcol == col.colname && 
				fil.operation == op &&
				fil.tform == col.transform ) {
				return false;
		}
	}
	return true;
}
*/

/* adds an item to the display window */
function oilsAddRptAggFilterItem(val) {
	oilsAddSelectorItem(oilsRptHavingFilterSelector, val);
}

/* removes a specific item from the display window */
function oilsDelAggFilterItem(val) {
	oilsDelSelectorItem(oilsRptHavingFilterSelector, val);
}



/*
function ___oilsDelSelectedAggFilterItems() {
	var list = oilsDelSelectedItems(oilsRptHavingFilterSelector);
	oilsRpt.def.having = grep( oilsRpt.def.having, 
		function(i) {
			for( var j = 0; j < list.length; j++ ) {
				var d = list[j];
				var col = i.column;

				if( typeof col != 'string' ) 
					for( var c in col ) col = col[c];

				if( typeof col != 'string' ) col = col[0];

				if( oilsRptPathRel(d) == i.relation && oilsRptPathCol(d) == col ) {
				*/
				//	var param = (i.alias) ? i.alias.match(/::P\d*/) : null;
					/*
					if( param ) delete oilsRpt.params[param];
					return false;
				}
			}
			return true;
		}
	);

	if(!oilsRpt.def.having) oilsRpt.def.having = [];
	oilsRptPruneFromList(list);
	oilsRptDebug();
}
*/


/* adds an item to the display window */
function oilsAddSelectorItem(sel, val, name) {
	name = (name) ? name : oilsRptMakeLabel(val);
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		if( opt.value == val ) return false;
	}
	insertSelectorVal( sel, -1, name, val );
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
}


/**
  This draws the 3-tabbed window containing the transform,
  filter, and aggregate filter picker window
  */
function oilsRptDrawDataWindow(path) {
	var col	= oilsRptPathCol(path);
	var cls	= oilsRptPathClass(path);
	var field = oilsRptFindField(oilsIDL[cls], col);

	appendClear(DOM.oils_rpt_editor_window_label, text(oilsRptMakeLabel(path)));
	appendClear(DOM.oils_rpt_editor_window_datatype, text(field.datatype));

	_debug("setting update data window for column "+col+' on class '+cls);

	var div = DOM.oils_rpt_column_editor;
	/* set a preliminary top position so the page won't bounce around */
	div.setAttribute('style','top:'+oilsMouseX+'px');

	/* unhide the div so we can determine the dimensions */
	unHideMe(div);

	/* don't let them see the floating div until the position is fully determined */
	div.style.visibility='hidden'; 

	oilsRptDrawTransformWindow(path, col, cls, field);
	oilsRptDrawFilterWindow(path, col, cls, field);
	oilsRptDrawHavingWindow(path, col, cls, field);
	oilsRptDrawOrderByWindow(path, col, cls, field);

	buildFloatingDiv(div, 600);

	/* now let them see it */
	div.style.visibility='visible';
	oilsRptSetDataWindowActions(div);
}


function oilsRptSetDataWindowActions(div) {
	/* give the tab links behavior */
	DOM.oils_rpt_tform_tab.onclick = 
		function(){oilsRptHideEditorDivs();unHideMe(DOM.oils_rpt_tform_div)};
	DOM.oils_rpt_filter_tab.onclick = 
		function(){oilsRptHideEditorDivs();unHideMe(DOM.oils_rpt_filter_div)};
	DOM.oils_rpt_agg_filter_tab.onclick = 
		function(){oilsRptHideEditorDivs();unHideMe(DOM.oils_rpt_agg_filter_div)};

	DOM.oils_rpt_order_by_tab.onclick = 
		function(){
			oilsRptHideEditorDivs();
			oilsRptDrawOrderByWindow();
			unHideMe(DOM.oils_rpt_order_by_div);
			};

	DOM.oils_rpt_tform_tab.onclick();
	DOM.oils_rpt_column_editor_close_button.onclick = function(){hideMe(div);};
}


function oilsRptDrawFilterWindow(path, col, cls, field) {

	var tformPicker = new oilsRptTformPicker( {	
			node : DOM.oils_rpt_filter_tform_table,
			datatype : field.datatype,
			non_aggregate : true
		}
	);

	var filterPicker = new oilsRptFilterPicker({
			node : DOM.oils_rpt_filter_op_table,
			datatype : field.datatype
		}
	);

	DOM.oils_rpt_filter_submit.onclick = function() {
		oilsAddRptFilterItem(
			path, tformPicker.getSelected(), filterPicker.getSelected());
	}
}


function oilsRptDrawHavingWindow(path, col, cls, field) {
	var tformPicker = new oilsRptTformPicker( {	
			node : DOM.oils_rpt_agg_filter_tform_table,
			datatype : field.datatype,
			aggregate : true
		}
	);

	var filterPicker = new oilsRptFilterPicker({
			node : DOM.oils_rpt_agg_filter_op_table,
			datatype : field.datatype
		}
	);

	DOM.oils_rpt_agg_filter_submit.onclick = function() {
		oilsAddRptHavingItem(
			path, tformPicker.getSelected(), filterPicker.getSelected());
	}
}

/* draws the transform window */
function oilsRptDrawTransformWindow(path, col, cls, field) {
	DOM.oils_rpt_tform_label_input.value = oilsRptMakeLabel(path);
	var dtype = field.datatype;

	var tformPicker = new oilsRptTformPicker( {	
			node : DOM.oils_rpt_tform_table,
			datatype : field.datatype,
			non_aggregate : true,
			aggregate : true
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



