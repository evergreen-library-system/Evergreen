function oilsRptSplitPath(path) {
	var parts = path.split(/-/);
	var column = parts.pop();
	return [ parts.join('-'), column ];
}

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
			var f = grep(data.fields, function(j){return (j.name == column); })[0];
			str += ":"+f.label;
		}
	}
	return str;
}


/* adds an item to the display window */
function oilsAddRptDisplayItem(val) {
	if( ! oilsAddSelectorItem(oilsRptDisplaySelector, val) ) 
		return;

	/* add the selected columns to the report output */
	var splitp = oilsRptSplitPath(val);
	oilsRpt.select.push( {relation:splitp[0], column:splitp[1]} );
	oilsRptDebug();
}

/* removes a specific item from the display window */
function oilsDelDisplayItem(val) {
	oilsDelSelectorItem(oilsRptDisplaySelector, val);
}

/* removes selected items from the display window */
function oilsDelSelectedDisplayItems() {
	var list = oilsDelSelectedItems(oilsRptDisplaySelector);

	/* remove the de-selected columns from the report output */
	oilsRpt.select = grep( oilsRpt.select, 
		function(i) {
			for( var j = 0; j < list.length; j++ ) {
				var d = list[j];
				var arr = oilsRptSplitPath(d);
				_debug(arr);
				if( arr[0] == i.relation && arr[1] == i.column ) return false;
			}
			return true;
		}
	);
	if(!oilsRpt.select) oilsRpt.select = [];
	oilsRptDebug();
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
function oilsAddSelectorItem(sel, val) {
	var name = oilsRptMakeLabel(val);
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


function oilsRptDrawDataWindow(path) {

	var parts = path.split(/-/);
	var col = parts.pop();
	var cls = parts.pop();
	var field = grep(oilsIDL[cls].fields, function(f){return (f.name==col);})[0];
	_debug("setting update data window for column "+col+' on class '+cls);

	var div = $('oils_rpt_column_editor');

	unHideMe(div);
	/* don't let them see it until the position is fully determined */
	div.style.visibility='hidden'; 

	oilsRptDrawTransformWindow(path, col, cls, field);

	$('oils_rpt_column_editor_close_button').onclick = function(){hideMe(div);};
	buildFloatingDiv(div, 600);
	div.style.visibility='visible';

	/* focus after all the shifting to make sure the div is at least visible */
	$('oils_rpt_tform_label_input').focus();
}


function oilsRptDrawTransformWindow(path, col, cls, field) {
	appendClear($('oils_rpt_tform_label'), text(oilsRptMakeLabel(path)));
	$('oils_rpt_tform_label_input').value = oilsRptMakeLabel(path);

	$('oils_rpt_tform_submit').onclick = 
		function(){ oilsAddRptDisplayItem(path, $('oils_rpt_tform_label_input').value) };

	$('oils_rpt_tform_label_input').focus();
	$('oils_rpt_tform_label_input').select();
}



