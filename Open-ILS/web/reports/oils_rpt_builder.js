/** initializes reports, some basid display settings, 
  * grabs and builds the IDL tree
  */
function oilsInitReportBuilder() {
	oilsInitReports();
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
	oilsRpt.folder = new CGI().param('folder');
}

function oilsReportBuilderReset() {
	var n = (oilsRpt) ? oilsRpt.name : "";
	oilsRpt = new oilsReport();
	oilsRpt.name = n;
	oilsRptDisplaySelector	= DOM.oils_rpt_display_selector;
	oilsRptFilterSelector	= DOM.oils_rpt_filter_selector;
	oilsRptAggFilterSelector= DOM.oils_rpt_agg_filter_selector;
	removeChildren(oilsRptDisplaySelector);
	removeChildren(oilsRptFilterSelector);
	removeChildren(oilsRptAggFilterSelector);
	oilsRptDebug();
	oilsRptResetParams();
}

function oilsReportBuilderSave() {
	if(!confirm('Name : '+oilsRpt.name + '\nDescription: ' 
			+ oilsRpt.description+'\nSave Template?'))
		return;

	var tmpl = new rt();
	tmpl.name( oilsRpt.name );
	tmpl.description( oilsRpt.desc );
	tmpl.ower(USER.id());
	tmpl.folder(oilsRpt.folder);
	tmpl.data(js2JSON(oilsRpt.def));

	var req = new Request(OILS_RPT_CREATE_TEMPLATE, SESSION, tmpl);
	req.callback(
		function(r) {
			var res = r.getResultObject();
			if( res != 0 ) {
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

	/* add this item to the select blob */
	var sel = {
		relation: oilsRptPathRel(path), 
		alias:    name,
		column:   { transform: tform, colname: oilsRptPathCol(path) }
	};

	if( params ) sel.column.params = params;
	oilsRpt.def.select.push(sel);

	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRptDebug();
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
		tobj.alias = newpath;
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

	/* remove the de-selected columns from the report output */
	oilsRpt.def.select = grep( oilsRpt.def.select, 
		function(i) {
			for( var j = 0; j < list.length; j++ ) {
				var d = list[j];
				var col = i.column;

				if( oilsRptPathRel(d) == i.relation && oilsRptPathCol(d) == col.colname ) {
					//var param = (i.alias) ? i.alias.match(/::PARAM\d*/) : null;
					//	if( param ) delete oilsRpt.params[param];
					return false;
				}
			}
			return true;
		}
	);

	if(!oilsRpt.def.select) {
		oilsRpt.def.select = [];
		//oilsReportBuilderReset();

	} else {
		for( var j = 0; j < list.length; j++ ) 
			/* if there are no items left in the "select", "where", or "having" clauses 
				for the given relation, trim this relation from the "from" clause */
			if(	!grep(oilsRpt.def.select,
					function(i){ return (i.relation == oilsRptPathRel(list[j])); })
				&& !grep(oilsRpt.def.where,
					function(i){ return (i.relation == oilsRptPathRel(list[j])); })
				&& !grep(oilsRpt.def.having,
					function(i){ return (i.relation == oilsRptPathRel(list[j])); })
			) oilsRptPruneFromClause(oilsRptPathRel(list[j]));
	}

	oilsRptDebug();
}


/* for each item in the path list, remove the associated data
	from the "from" clause */

function oilsRptPruneFromClause(relation, node) {
	_debug("removing relation from 'from' clause " + relation);
	if(!node) node = oilsRpt.def.from.join;
	for( var i in node ) {
		_debug("looking at node "+node[i].alias);
		if( node[i].alias == relation ) {
			if( node[i].join ) {
				/* if we have subtrees, don't delete our tree node */
				return false;
			} else {
				delete node[i];
				return true;
			} 
		} else {
			if( node[i].join ) {
				if( oilsRptPruneFromClause(relation, node[i].join ) ) {
					if(oilsRptObjectKeys(node[i].join).length == 0) {
						delete node[i].join;
						/* if there are no items in the select clause with a relation matching
							this nodes alias, we can safely remove this node from the tree */
						if(!grep(oilsRpt.def.select,function(r){return (r.relation==node[i].alias)}))
							delete node[i];
						return true;
					}
				}
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


/* adds an item to the display window */
function oilsAddRptFilterItem(path, tform, filter) {
	_debug("Adding filter item for "+path+" tform="+tform+" filter="+filter);

	var name = oilsRptMkFilterTags(path, tform, filter);
	var epath = name[1];
	name = name[0];

	if( ! oilsAddSelectorItem(oilsRptFilterSelector, epath, name) )
		return;

	var where = {
		relation: oilsRptPathRel(path), 
		column:   { transform: tform, colname: oilsRptPathCol(path) },
		condition : {}
	};
	where.condition[filter] = oilsRptNextParam();

	switch(tform) {
		case 'substring' : where.column.params = oilsRptNextParam();
	}

	oilsRpt.def.where.push(where);
	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRptDebug();
}

/* removes a specific item from the display window */
//function oilsDelFilterItem(path) {
	//oilsDelSelectorItem(oilsRptFilterSelector, path);
//}

/* removes selected items from the display window */
function oilsDelSelectedFilterItems() {

	/* the values in this list are formed:  <path>:<operation>:<transform> */
	var list = oilsDelSelectedItems(oilsRptFilterSelector);

	var flist = [];

	for( var i = 0; i < list.length; i++ ) {
		var item = list[i];
		flist.push( {
			path:		item.replace(/:.*/,''),
			operation:	item.replace(/.*:(.*):.*/,'$1'),
			tform:	item.replace(/.*?:.*?:(.*)/,'$1')
		});
	}


	/* XXX refactor the below to take operation and transform into account
		since the same path can be used multiple times as long as a different
		filter and/or transform is used */

	/* remove the de-selected columns from the report output */
	oilsRpt.def.where = grep( oilsRpt.def.where, 
		function(i) {
			for( var j = 0; j < flist.length; j++ ) {
				var fil = flist[j];
				var col = i.column;
				var frel = oilsRptPathRel(fil.path);
				var fcol = oilsRptPathCol(fil.path);

				var op = oilsRptObjectKeys(i.condition)[0];

				if(	frel == i.relation && 
						fcol == col.colname && 
						fil.operation == op &&
						fil.tform == col.transform ) {
						/* we have found a where clause with the same 
							relation, column,  operation and transform */
						
						/* we aren't setting params on template build.. */
						//var param = (i.column.params) ? i.columns.params.match(/::P\d*/) : null;
						//if( param ) delete oilsRpt.params[param];
						//param = (i.condition[op]) ? i.condition[op].match(/::P\d*/) : null;
						//if( param ) delete oilsRpt.params[param];

						return false;
				}
			}
			return true;
		}
	);

	if(!oilsRpt.def.where) 
		oilsRpt.def.where = [];


	for( var j = 0; j < flist.length; j++ ) {
		var path = flist[j].path;
		var rel = oilsRptPathRel(path);
		/* if there are no items left in the "select", "where", or "having" clauses 
			for the given relation, trim this relation from the "from" clause */

		var func = function(i){ return (i.relation == rel); };

		if(	!grep(oilsRpt.def.select, func) &&
				!grep(oilsRpt.def.where, func) &&
				!grep(oilsRpt.def.having, func) ) {

			_debug("pruning item with path "+ path + ' and relation '+ rel);

			oilsRptPruneFromClause(oilsRptPathRel(path)); 
		}
	}

	oilsRptDebug();
}

/* adds an item to the display window */
function oilsAddRptAggFilterItem(val) {
	oilsAddSelectorItem(oilsRptAggFilterSelector, val);
}

/* removes a specific item from the display window */
function oilsDelAggFilterItem(val) {
	oilsDelSelectorItem(oilsRptAggFilterSelector, val);
}

/* removes selected items from the display window */
function oilsDelSelectedAggFilterItems() {
	var list = oilsDelSelectedItems(oilsRptAggFilterSelector);

	/* remove the de-selected columns from the report output */
	oilsRpt.def.having = grep( oilsRpt.def.having, 
		function(i) {
			for( var j = 0; j < list.length; j++ ) {
				var d = list[j];
				var col = i.column;

				/* if this columsn has a transform, 
					it will be an object { tform => column } */
				if( typeof col != 'string' ) 
					for( var c in col ) col = col[c];

				/* if this transform requires params, the column 
					will be the first item in the param set array */
				if( typeof col != 'string' ) col = col[0];

				if( oilsRptPathRel(d) == i.relation && oilsRptPathCol(d) == col ) {
					var param = (i.alias) ? i.alias.match(/::P\d*/) : null;
					if( param ) delete oilsRpt.params[param];
					return false;
				}
			}
			return true;
		}
	);

	if(!oilsRpt.def.having) {
		oilsRpt.def.having = [];
		oilsReportBuilderReset();

	} else {
		for( var j = 0; j < list.length; j++ ) 
			/* if there are no items left in the "select", "where", or "having" clauses 
				for the given relation, trim this relation from the "from" clause */
			if(	!grep(oilsRpt.def.select,
					function(i){ return (i.relation == oilsRptPathRel(list[j])); })
				&& !grep(oilsRpt.def.where,
					function(i){ return (i.relation == oilsRptPathRel(list[j])); })
				&& !grep(oilsRpt.def.having,
					function(i){ return (i.relation == oilsRptPathRel(list[j])); })
			) oilsRptPruneFromClause(oilsRptPathRel(list[j]));
	}

	oilsRptDebug();
}


/* adds an item to the display window */
function oilsAddSelectorItem(sel, val, name) {
	name = (name) ? name : oilsRptMakeLabel(val);
	_debug("adding selector item "+name+' = ' +val);
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		if( opt.value == val ) return false;
	}
	insertSelectorVal( sel, -1, name, val );
	return true;
}


/* removes a specific item from the display window */
function oilsDelSelectorItem(sel, val) {
	_debug("deleting selector item "+val);
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

	//oilsRptSetFilters(field.datatype);

	//oilsRptDoFilterWidgets();

	//DOM.oils_rpt_filter_tform_selector.onchange = oilsRptDoFilterWidgets;

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

	DOM.oils_rpt_tform_tab.onclick();
	DOM.oils_rpt_column_editor_close_button.onclick = function(){hideMe(div);};
}


function oilsRptDrawFilterWindow(path, col, cls, field) {

	var fsel = $n(DOM.oils_rpt_filter_op_table,'selector');
	for( var i = 0; i < fsel.options.length; i++ ){
		var opt = fsel.options[i];
		var dt = opt.getAttribute('datatype');
		_debug(dt);

		/* add a special case for boolean objects, since the only 
			operation that makes sense is "="  */
		if( field.datatype == 'bool' ) {
			hideMe(opt);
			if( opt.getAttribute('value') == '=' )
				unHideMe(opt);

		} else {
			if( dt && dt != field.datatype )
				hideMe(opt);
			else unHideMe(opt);
		}
	}


	DOM.oils_rpt_filter_submit.onclick = function() {
		var tsel = $n(DOM.oils_rpt_filter_tform_table,'selector');
		var tform = getSelectorVal(tsel);
		var filter = getSelectorVal(fsel);
		oilsAddRptFilterItem(path, tform, filter);
	}
	oilsRptShowFilters($n(DOM.oils_rpt_filter_tform_table,'selector'), field.datatype, false, true);
		
	/*
	oilsRptCurrentFilterTform = new oilsRptTFormManager(DOM.oils_rpt_filter_tform_table);
	oilsRptCurrentFilterTform.build(field.datatype, false, true);
	oilsRptCurrentFilterOpManager = new oilsRptOpManager(DOM.oils_rpt_filter_op_table);
	*/
}

function oilsRptShowFilters( selector, dtype, show_agg, show_noagg ) {
	for( var i = 0; i < selector.options.length; i++ ) {
		var opt = selector.options[i];
		var t = opt.getAttribute('datatype');
		if( t && t != dtype ){
			hideMe(opt);
		} else {
			var ag = opt.getAttribute('aggregate');
			if( ag && show_agg )
				unHideMe(opt);
			else if( ag && ! show_agg )
				hideMe(opt)
			else if( !ag && show_noagg )
				unHideMe(opt);
			else hideMe(opt);
		}
	}
}


/* draws the transform window */
function oilsRptDrawTransformWindow(path, col, cls, field) {
	DOM.oils_rpt_tform_label_input.value = oilsRptMakeLabel(path);
	var dtype = field.datatype;

	DOM.oils_rpt_tform_submit.onclick = 
		function(){ 
			var sel = $n(DOM.oils_rpt_tform_table,'selector');
			var tform = getSelectorVal(sel);
			oilsAddRptDisplayItem(path, DOM.oils_rpt_tform_label_input.value, tform ) 
		};


	DOM.oils_rpt_tform_label_input.focus();
	DOM.oils_rpt_tform_label_input.select();

	/*
	oilsRptCurrentTform = new oilsRptTFormManager(DOM.oils_rpt_tform_table);
	oilsRptCurrentTform.build(dtype, true, true);
	*/

	_debug($n(DOM.oils_rpt_tform_table,'selector'));

	oilsRptShowFilters($n(DOM.oils_rpt_tform_table,'selector'), dtype, true, true);

	/*
	oilsRptHideTformFields();
	oilsRptUnHideTformFields(dtype);
	*/

	_debug("Building transform window for datatype "+dtype);

	/*
	unHideMe($('oils_rpt_tform_'+dtype+'_div'));
	$('oils_rpt_tform_all_raw').checked = true;
	*/
}

/*
function oilsRptHideTformFields() {
	var rows = DOM.oils_rpt_tform_tbody.childNodes;
	for( var i = 0; i < rows.length; i++ )
		if( rows[i] && rows[i].nodeType == 1 )
			hideMe(rows[i]);
}

function oilsRptUnHideTformFields(dtype) {
	var rows = DOM.oils_rpt_tform_tbody.childNodes;
	for( var i = 0; i < rows.length; i++ ) {
		var row = rows[i]
		if( row && row.nodeType == 1 && 
			(row.getAttribute('datatype')=='all' 
				|| row.getAttribute('datatype') == dtype)) {
			unHideMe(row);
		}
	}
}


function oilsRptGetTform(datatype) {
	for( var i in oilsRptTransforms[datatype] ) 
		if( $('oils_rpt_tform_'+datatype+'_'+oilsRptTransforms[datatype][i]).checked )
			return oilsRptTransforms[datatype][i];
	for( var i in oilsRptTransforms.all ) 
		if( $('oils_rpt_tform_all_'+oilsRptTransforms.all[i]).checked )
			return oilsRptTransforms.all[i];
	return null;
}
*/


/*
function getRptTformParams(type, tform) {
	switch(type) {
		case 'string' :
			switch(tform) {
				case 'substring' :
					return [
						DOM.oils_rpt_tform_string_substring_offset.value, 
						DOM.oils_rpt_tform_string_substring_length.value];
			}
	}
}
*/


/* given a transform selector, this displays the appropriate 
	transforms for the given datatype.
	if aggregate is true, is displays the aggregate transforms */
/*
function oilsRptSetTransforms(sel, dtype, show_agg, show_noagg) {
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		var t = opt.getAttribute('datatype');
		if( t && t != dtype ){
			hideMe(opt);
		} else {
			var ag = opt.getAttribute('aggregate');
			if( ag && show_agg )
				unHideMe(opt);
			else if( ag && ! show_agg )
				hideMe(opt)
			else if( !ag && show_noagg )
				unHideMe(opt);
			else
				hideMe(opt);
		}
	}
}
*/


/* displays the correct filter-transforms for the given datatype */
/*
function oilsRptSetFilters(dtype) {

	DOM.oils_rpt_filter_submit.onclick = function() {
		var data = oilsRptDoFilterWidgets();
		alert(js2JSON(data));
	}

	var sel = DOM.oils_rpt_filter_tform_selector;
	for( var i = 0; i < sel.options.length; i++ ) {
		var opt = sel.options[i];
		_debug(opt.getAttribute('op'));
		var t = opt.getAttribute('datatype');
		if( t && t != dtype ) hideMe(opt);
		else unHideMe(opt);
	}
}
*/

/* hides all of the filter widgets */
function oilsRptHideFilterWidgets(node) {
	if(!node)
		node = DOM.oils_rpt_filter_tform_widget_td;
	if( node.nodeType != 1 ) return;
	if( node.getAttribute('widget') ) {
		hideMe(node);
	} else {
		var cs = node.childNodes;
		for( var i = 0; cs && i < cs.length; i++ )
			oilsRptHideFilterWidgets(cs[i]);
	}
}

/* what does this need to do? */
function oilsRptSetFilterOpActions() {
}



/* hides/unhides the appropriate widgets and returns the parameter
	array appropriate for the selected widget */
function oilsRptDoFilterWidgets() {
	filter = getSelectorVal(DOM.oils_rpt_filter_tform_selector);
	oilsRptHideFilterWidgets();
	var op = null;
	var tform = null;
	var params = null;

	switch(filter) {
		
		/* generic transforms */
		case 'equals':
			if(!op) op = 'equals';
		case 'like':
			if(!op) op = 'like';
		case 'ilike':
			if(!op) op = 'ilike';
		case 'gt':
			if(!op) op = '>';
		case 'gte':
			if(!op) op = '>=';
		case 'lt':
			if(!op) op = '<';
		case 'lte':
			if(!op) op = '<=';
		case 'in':
			if(!op) op = 'in';
		case 'not_in':
			if(!op) op = 'not in';
		case 'between':
			if(!op) op = 'between';
		case 'not_between':
			if(!op) op = 'not between';
			unHideMe(DOM.oils_rpt_filter_tform_input);	
			params = [DOM.oils_rpt_filter_tform_input.value];
			break;

		/* timestamp transforms */
		case 'date_between':
			if(!op) op = 'between';
		case 'date_not_between':
			if(!op) op = 'not between';
			tform = 'date';
			var d = new Date();
			unHideMe(DOM.oils_rpt_filter_tform_date_1);
			unHideMe(DOM.oils_rpt_filter_tform_date_2);
			unHideMe(DOM.oils_rpt_filter_tform_date_hint);
			DOM.oils_rpt_filter_tform_date_1.value = mkYearMonDay();
			DOM.oils_rpt_filter_tform_date_2.value = mkYearMonDay();
			params = [
				DOM.oils_rpt_filter_tform_date_1.value,
				DOM.oils_rpt_filter_tform_date_2.value
			];
			break;

		case 'dow_between':
			op = 'between';
			if(!tform) tform = 'dow';
		case 'dow_not_between':
			if(!op) op = 'not between';
			if(!tform) tform = 'dow';
			break;

		case 'dom_between':
			op = 'between';
			if(!tform) tform = 'dom';
		case 'dom_not_between':
			if(!op) op = 'not between';
			if(!tform) tform = 'dom';
			break;

		case 'month_between':
			op = 'between';
			if(!tform) tform = 'moy';
		case 'month_not_between':
			if(!op) op = 'not between';
			if(!tform) tform = 'moy';
			break;

		case 'quarter_between':
			op = 'between';
			if(!tform) tform = 'qoy';
		case 'quarter_not_between':
			if(!op) op = 'not between';
			if(!tform) tform = 'qoy';
			break;

		case 'year_between':
			if(!op) op = 'between';
			if(!tform) tform = 'year_trunc';
		case 'year_not_between':
			if(!op) op = 'not between';
			if(!tform) tform = 'year_trunc';
			break;

		case 'age_between':
			if(!op) op = 'between';
			if(!tform) tform = 'age';
		case 'age_not_between':
			if(!op) op = 'not between';
			if(!tform) tform = 'age';
			break;

		/* string transforms */
		case 'substring':
			if(!tform) tform = 'substring';
			break;

		case 'lower':
			if(!op) op = '';
			if(!tform) tform = 'dow';

		case 'upper':
			if(!op) op = '';
			if(!tform) tform = 'dow';

		/* numeric transforms */
		case 'round':
			if(!op) op = '';
			if(!tform) tform = 'dow';

		case 'int':
			if(!op) op = '';
			if(!tform) tform = 'dow';
	}

	return { op : op, params : params, tform : tform };
}




