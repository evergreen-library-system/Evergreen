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
	var n = (oilsRpt) ? oilsRpt.name : "";
	oilsRpt = new oilsReport();
	oilsRpt.name = n;
	oilsRptDisplaySelector	= DOM.oils_rpt_display_selector;
	oilsRptFilterSelector	= DOM.oils_rpt_filter_selector;
	removeChildren(oilsRptDisplaySelector);
	removeChildren(oilsRptFilterSelector);
	oilsRptDebug();
	oilsRptResetParams();
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
function oilsAddRptDisplayItem(path, name, tform, params) {
	if( ! oilsAddSelectorItem(oilsRptDisplaySelector, path, name) ) 
		return;

	/* add the selected columns to the report output */
	name = (name) ? name : oilsRptPathCol(path);
	var param = oilsRptNextParam();

	/* add this item to the select blob */
	var sel = {
		relation:oilsRptPathRel(path), 
		alias:param
	};

	if( tform ) {
		sel.column = {};
		if( params ) {
			params.unshift(oilsRptPathCol(path));
			sel.column[tform] = params;
		} else {
			sel.column[tform] = oilsRptPathCol(path); 
		}
	} else { sel.column = oilsRptPathCol(path); }

	oilsRpt.def.select.push(sel);

	mergeObjects( oilsRpt.def.from, oilsRptBuildFromClause(path));
	oilsRpt.params[param] = name;
	oilsRptDebug();
}

/* takes a column path and builds a from-clause object for the path */
function oilsRptBuildFromClause(path) {
	var parts = path.split(/-/);
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
				var col = i.column;

				/* if this columsn has a transform, 
					it will be an object { tform => column } */
				if( typeof col != 'string' ) 
					for( var c in col ) col = col[c];

				/* if this transform requires params, the column 
					will be the first item in the param set array */
				if( typeof col != 'string' ) col = col[0];

				if( oilsRptPathRel(d) == i.relation && oilsRptPathCol(d) == col ) {
					var param = (i.alias) ? i.alias.match(/::PARAM\d*/) : null;
					if( param ) delete oilsRpt.params[param];
					return false;
				}
			}
			return true;
		}
	);

	if(!oilsRpt.def.select) {
		oilsRpt.def.select = [];
		oilsReportBuilderReset();

	} else {
		for( var j = 0; j < list.length; j++ ) 
			oilsRptPruneFromClause(list[j]);
	}

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

	DOM.oils_rpt_tform_tab.onclick();
}


/* draws the transform window */
function oilsRptDrawTransformWindow(path, col, cls, field) {
	appendClear(DOM.oils_rpt_tform_label, text(oilsRptMakeLabel(path)));
	DOM.oils_rpt_tform_label_input.value = oilsRptMakeLabel(path);
	var dtype = field.datatype;

	DOM.oils_rpt_tform_submit.onclick = 
		function(){ 
			var tform = oilsRptGetTform(dtype);
			_debug('found tform: ' + js2JSON(tform));
			var params = getRptTformParams(dtype, tform);
			_debug('found tform params: ' + js2JSON(params));
			tform = (tform == 'raw') ? null : tform;
			oilsAddRptDisplayItem(path, DOM.oils_rpt_tform_label_input.value, tform, params ) 
		};

	DOM.oils_rpt_tform_label_input.focus();
	DOM.oils_rpt_tform_label_input.select();
	oilsRptHideTformFields();

	_debug("Transforming item with datatype "+dtype);
	unHideMe($('oils_rpt_tform_'+dtype+'_div'));
	$('oils_rpt_tform_all_raw').checked = true;
}

function oilsRptHideTformFields() {
	for( var t in oilsRptTransforms ) 
		hideMe($('oils_rpt_tform_'+t+'_div'));
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

function getRptTformParams(type, tform) {
	switch(type) {
		case 'timestamp':
			switch(tform) {
				case 'months_ago':
					return [DOM.oils_rpt_tform_timestamp_months_ago_input.value];
				case 'quarters_ago':
					return [DOM.oils_rpt_tform_timestamp_quarters_ago_input.value];
			}
		case 'string' :
			switch(tform) {
				case 'substring' :
					return [];
			}
	}
}


