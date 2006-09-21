/** initializes reports, some basid display settings, 
  * grabs and builds the IDL tree
  */
function oilsInitReportBuilder() {
	oilsInitReports();
	oilsReportBuilderReset();
	oilsDrawRptTree(
		function() { 
			hideMe(DOM.oils_rpt_tree_loading); 
			unHideMe(DOM.oils_rpt_table); 
		}
	);
}

function oilsReportBuilderReset() {
	oilsRpt = new oilsReport();
	oilsRptDisplaySelector	= DOM.oils_rpt_display_selector;
	oilsRptFilterSelector	= DOM.oils_rpt_filter_selector;
	removeChildren(oilsRptDisplaySelector);
	removeChildren(oilsRptFilterSelector);
	oilsRptDebug();
}

/* returns just the column name */
function oilsRptPathCol(path) {
	var parts = path.split(/-/);
	return parts.pop();
}

/* returns the IDL class of the selected column */
function oilsRptPathClass(path) {
	var parts = path.split(/-/);
	parts.pop();
	return parts.pop();
}

/* returns everything prior to the column name */
function oilsRptPathRel(path) {
	var parts = path.split(/-/);
	parts.pop();
	return parts.join('-');
}

/* creates a label "path" based on the column path */
function oilsRptMakeLabel(path) {
	var parts = path.split(/-/);
	var str = '';
	for( var i = 0; i < parts.length; i++ ) {
		if(i%2 == 0) {
			if( i == 0 )
				str += oilsIDL[parts[i]].label;
		} else {
			var column = parts[i];
			var data = oilsIDL[parts[i-1]];
			var f = grep(data.fields, 
				function(j){return (j.name == column); })[0];
			str += ":"+f.label;
		}
	}
	return str;
}


/* adds an item to the display window */
function oilsAddRptDisplayItem(path, name) {
	if( ! oilsAddSelectorItem(oilsRptDisplaySelector, path, name) ) 
		return;

	/* add the selected columns to the report output */
	name = (name) ? name : oilsRptPathCol(path);
	var param = oilsRptNextParam();

	/* add this item to the select blob */
	oilsRpt.def.select.push( {
		relation:oilsRptPathRel(path), 
		column:oilsRptPathCol(path), 
		alias:param
	});

	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRpt.params[param] = name;
	oilsRptDebug();
}

/* takes a column path and builds a from-clause object for the path */
function oilsRptBuildFromClause(path) {
	var parts = path.split(/-/);
	//var obj = {from : {}};
	var obj = {};
	var tobj = obj;
	var newpath = "";
	for( var i = 0; i < parts.length; i += 2 ) {
		var cls = parts[i];
		var col = parts[i+1];
		var node = oilsIDL[parts[i]];
		var field = oilsRptFindField(node, col);
		newpath = (newpath) ? newpath + '-'+ cls : cls;

		tobj.table = node.table;
		tobj.alias = newpath;
		_debug('field type is ' + field.type);
		if( i == (parts.length - 2) ) break;

		tobj.join = {};
		tobj = tobj.join;
		tobj[col] = {};
		tobj = tobj[col];
		if( field.type == 'link' )
			tobj.key = field.key;

		newpath = newpath + '-'+ col;
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
				if( oilsRptPathRel(d) == i.relation 
						&& oilsRptPathCol(d) == i.column ) {
					var param = (i.alias) ? i.alias.match(/::PARAM\d*/) : null;
					if( param ) delete oilsRpt.params[param];
					return false;
				}
			}
			return true;
		}
	);
	if(!oilsRpt.def.select) oilsRpt.def.select = [];

	for( var j = 0; j < list.length; j++ ) 
		oilsRptPruneFromClause(list[j]);

	oilsRptDebug();
}

/* for each item in the path list, remove the associated data
from the "from" clause */
function oilsRptPruneFromClause(pathlist) {
}

/* adds an item to the display window */
function oilsAddRptFilterItem(val) {
	oilsAddSelectorItem(oilsRptFilterSelector, val);
}

/* removes a specific item from the display window */
function oilsDelFilterItem(val) {
	oilsDelSelectorItem(oilsRptFilterSelector, val);
}

/* removes selected items from the display window */
function oilsDelSelectedFilterItems() {
	oilsDelSelectedItems(oilsRptFilterSelector);
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
	var col = oilsRptPathCol(path);
	var cls = oilsRptPathClass(path);
	var field = grep(oilsIDL[cls].fields, function(f){return (f.name==col);})[0];
	_debug("setting update data window for column "+col+' on class '+cls);

	var div = DOM.oils_rpt_column_editor;
	/* set a preliminary top position so the page won't bounce around */
	div.setAttribute('style','top:'+oilsMouseX+'px');

	/* unhide the div so we can determine the dimensions */
	unHideMe(div);

	/* don't let them see the floating div until the position is fully determined */
	div.style.visibility='hidden'; 

	oilsRptDrawTransformWindow(path, col, cls, field);

	DOM.oils_rpt_column_editor_close_button.onclick = function(){hideMe(div);};
	buildFloatingDiv(div, 600);

	/* now let them see it */
	div.style.visibility='visible';

	/* give the tab links behavior */
	DOM.oils_rpt_tform_tab.onclick = 
		function(){oilsRptHideEditorDivs();unHideMe(DOM.oils_rpt_tform_div)};
	DOM.oils_rpt_filter_tab.onclick = 
		function(){oilsRptHideEditorDivs();unHideMe(DOM.oils_rpt_filter_div)};
	DOM.oils_rpt_agg_filter_tab.onclick = 
		function(){oilsRptHideEditorDivs();unHideMe(DOM.oils_rpt_agg_filter_div)};
}


/* draws the transform window */
function oilsRptDrawTransformWindow(path, col, cls, field) {
	appendClear(DOM.oils_rpt_tform_label, text(oilsRptMakeLabel(path)));
	DOM.oils_rpt_tform_label_input.value = oilsRptMakeLabel(path);

	DOM.oils_rpt_tform_submit.onclick = 
		function(){ oilsAddRptDisplayItem(path, DOM.oils_rpt_tform_label_input.value) };

	DOM.oils_rpt_tform_label_input.focus();
	DOM.oils_rpt_tform_label_input.select();

	if( field.datatype == 'timestamp' )
		unHideMe(DOM.oils_rpt_tform_date_div);
}



