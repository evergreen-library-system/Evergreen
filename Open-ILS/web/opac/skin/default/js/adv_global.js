
attachEvt("common", "run", advgInit);

function advgInit() {

	$n($('adv_global_tbody'), 'term').focus();

	var extras = [ 
		FETCH_LIT_FORMS, 
		FETCH_ITEM_FORMS, 
		FETCH_ITEM_TYPES, 
		FETCH_AUDIENCES ];

	for( var x in extras ) {

		var req = new Request(extras[x]);

		if(x == 0) req.request.sel = $('adv_global_lit_form');
		if(x == 1) req.request.sel = $('adv_global_item_form');
		if(x == 2) req.request.sel = $('adv_global_item_type');
		if(x == 3) req.request.sel = $('adv_global_audience');

		req.callback(advDrawBibExtras);
		req.send();
	}

	var input = $n($('adv_global_trow'), 'term');
	input.focus();
	setEnterFunc(input, advSubmitGlobal);
}

function advDrawBibExtras(r) {
	var data = r.getResultObject();
	var sel = r.sel;

	data = data.sort( /* sort alphabetically */
		function(a,b) { 
			if( a.value() < b.value() ) return -1;
			if( a.value() > b.value() ) return 1;
			return 0;
		}
	);

	for( var d = 0; d < data.length; d++ ) {
		var thing = data[d];
		var opt = insertSelectorVal( sel, -1, thing.value(), thing.code() );
		opt.setAttribute('title', thing.value());
	}
}

function advSelToStringList(sel) {
	var list = getSelectedList(sel);
	var vals = [];
	for( var i = 0; i < list.length; i++ ) {
		var str = list[i];
		for( var j = 0; j < str.length; j++ ) {
			if(str.charAt(j) == ' ') continue;
			vals.push(str.charAt(j));
		}
	}
	return vals.toString();
}

function advGetVisSelectorVals(id) {
	var basic = id + '_basic';
	if(! $(id).className.match(/hide_me/)) 
		return advSelToStringList($(id));
	return advSelToStringList($(basic));
}

function advSubmitGlobal() {
	
	var sortdir = getSelectorVal($('adv_global_sort_dir'));
	var sortby  = getSelectorVal($('adv_global_sort_by'));

	var litforms  = advGetVisSelectorVals('adv_global_lit_form');
	var itemforms = advGetVisSelectorVals('adv_global_item_form');
	var itemtypes = advGetVisSelectorVals('adv_global_item_type');
	var audiences = advGetVisSelectorVals('adv_global_audience');
	var languages = getSelectedList($('adv_global_lang')) + '';	

	var searches = advBuildSearchBlob();
	if(!searches) return;

	clearSearchParams();

	var args = {};
	args.page = MRESULT;
	args[PARAM_ITEMFORM] = itemforms;
	args[PARAM_ITEMTYPE] = itemtypes;
	args[PARAM_LITFORM]	= litforms;
	args[PARAM_AUDIENCE]	= audiences;
	args[PARAM_LANGUAGE] = languages;
	args[PARAM_SEARCHES]	= js2JSON(searches); /* break these out */
	args[PARAM_DEPTH]		= depthSelGetDepth();
	args[PARAM_LOCATION]	= depthSelGetNewLoc();
	args[PARAM_SORT]		= sortby;
	args[PARAM_SORT_DIR]	= sortdir;
	args[PARAM_ADVTYPE]	= ADVTYPE_MULTI;
	args[PARAM_STYPE]		= "";
	args[PARAM_TERM]		= "";

	/* pubdate sorting causes a record (not metarecord) search */
	if( sortby == SORT_TYPE_PUBDATE ) {
		args.page = RRESULT;
		args[PARAM_RTYPE] = RTYPE_MULTI;
	}

	goTo(buildOPACLink(args));
}


function advBuildSearchBlob() {

	var searches;
	var tbody    = $('adv_global_tbody');
	var rows     = tbody.getElementsByTagName('tr');

	for( var i = 0; i < rows.length; i++ ) {

		var row = rows[i];
		if(!(row && typeof row == 'object')) continue;
		if(!row.getAttribute('type')) continue;
		
		var stype	 = getSelectorVal($n(row, 'type'));
		var contains = getSelectorVal($n(row, 'contains'));
		var term		 = $n(row, 'term').value;
		if(!term) continue;

		var string = "";
		if(!searches) searches = {};
		if(searches[stype]) 
			string = searches[stype].term;
		else searches[stype] = {};

		switch(contains) {
			case 'contains' : 
				string += " " + term; 
				break;

			case 'nocontains' : {
				var words = term.split(" ");
					for( var i in words ) 
						string += " -" + words[i];
				}
				break;

			case 'exact' : 
				if(term.indexOf('"') > -1) string += " " + term;
				else string += " \"" + term + "\"";
				break;
		}
		if(string) searches[stype].term = string;
	}

	return searches;
}




