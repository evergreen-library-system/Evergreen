/* advanced search interface */

attachEvt("common", "run", advInit);

function advInit() { 

	/* propogate these? */

	depthSelInit(); 
	setEnterFunc( $n( $('advanced.marc.tbody'), 'advanced.marc.value'), advMARCRun );

	unHideMe($('adv_quick_search_sidebar'));

	/*
	if(isXUL()) 
		setSelector($('adv_quick_type'), 'tcn'); */

	setEnterFunc($('adv_quick_text'), advGenericSearch);

	unHideMe($('adv_marc_search_sidebar'));
}


function advAddMARC() {
	var newt = $('adv_sdbar_table').cloneNode(true);
	newt.id = "";
	unHideMe($n(newt, 'crow'));
	$n(newt, 'advanced.marc.tag').value = "";
	$n(newt, 'advanced.marc.subfield').value = "";
	$n(newt, 'advanced.marc.value').value = "";
	$('adv_marc_search_sidebar').insertBefore(newt, $('adv_marc_submit'));
}

function advMARCRun() {

	clearSearchParams();

	var div = $('adv_marc_search_sidebar');
	var tbodies = div.getElementsByTagName('tbody');
	var searches = [];

	for( var i = 0; i < tbodies.length; i++ ) {
		var tbody = tbodies[i];
		var val = advExtractMARC(tbody);
		if(val) searches.push(val);
	}

	if(searches.length == 0) return;

	var arg = {};
	arg.page = RRESULT;
	arg[PARAM_FORM] = 'all'
	arg[PARAM_RTYPE] = RTYPE_MARC;
	arg[PARAM_OFFSET] = 0;
	arg[PARAM_DEPTH]	= depthSelGetDepth();
	arg[PARAM_LOCATION]	= depthSelGetNewLoc();
	arg[PARAM_SEARCHES] = js2JSON(searches);
	arg[PARAM_ADVTYPE] = ADVTYPE_MARC;
	arg[PARAM_TERM] = "";

	goTo(buildOPACLink(arg));
}


/* EXAMPLE => {"term":"0516011901","restrict":[{"tag":"020","subfield":"a"}]} */
function advExtractMARC(tbody) {
	if(!tbody) return null;
	var term = $n(tbody, 'advanced.marc.value').value;
	if(!term) return null;

	var subfield = $n(tbody, 'advanced.marc.subfield').value;
	if(!subfield) subfield = "_";

	var tag = $n(tbody, 'advanced.marc.tag').value;
	if(!tag) return null;

	return { 'term' : term.toLowerCase(), 'restrict' :  [ { 'tag' : tag, 'subfield' : subfield } ] };
}

function advGenericSearch() {
	clearSearchParams();
	var type = getSelectorVal($('adv_quick_type'));
	
	var term = $('adv_quick_text').value;
	if(!term) return;

	var arg = {};

	switch(type) {

		case 'isbn' :
			arg.page					= RRESULT;
			arg[PARAM_STYPE]		= "";
			arg[PARAM_TERM]		= "";
			arg[PARAM_RTYPE]		= RTYPE_ISBN;
			arg[PARAM_OFFSET]		= 0;
			arg[PARAM_ADVTERM]	= term.toLowerCase();
			break;
		
		case 'issn' :
			arg.page					= RRESULT;
			arg[PARAM_STYPE]		= "";
			arg[PARAM_TERM]		= "";
			arg[PARAM_ADVTERM]	= term.toLowerCase();
			arg[PARAM_OFFSET]		= 0;
			arg[PARAM_RTYPE]		= RTYPE_ISSN;
			break;

		case 'tcn' :
			arg.page					= RRESULT;
			arg[PARAM_STYPE]		= "";
			arg[PARAM_TERM]		= "";
			arg[PARAM_ADVTERM]	= term;
			arg[PARAM_OFFSET]		= 0;
			arg[PARAM_RTYPE]		= RTYPE_TCN;
			break;

        case 'barcode':
            advFindBarcode(term);
            break;


		case 'cn':
			arg.page			= CNBROWSE;
			arg[PARAM_CN]	= term;
			arg[PARAM_DEPTH]		= depthSelGetDepth();
			arg[PARAM_LOCATION]	= depthSelGetNewLoc();
			break;

		case 'lccn':
			arg.page = RRESULT;
			arg[PARAM_FORM] = 'all'
			arg[PARAM_RTYPE] = RTYPE_MARC;
			arg[PARAM_OFFSET] = 0;
			arg[PARAM_DEPTH]	= depthSelGetDepth();
			arg[PARAM_LOCATION]	= depthSelGetNewLoc();
			arg[PARAM_SEARCHES] = js2JSON([{ 'term' : term.toLowerCase(), 
					'restrict' :  [ { 'tag' : '010', 'subfield' : '_' } ] }]);
			arg[PARAM_ADVTYPE] = ADVTYPE_MARC;
			arg[PARAM_TERM] = "";
			break;


		default: alert('not done');
	}

	if(arg.page) goTo(buildOPACLink(arg));
}


function advFindBarcode(barcode) {
    var req = new Request(FETCH_BIB_IDS_BY_BARCODE, barcode);
    req.callback(advDrawBarcode);
    req.request.alertEvent = false;
    req.send();
}

function advDrawBarcode(r) {
    var title_ids = r.getResultObject();
    if(checkILSEvent(title_ids)) {
        alertId('myopac.copy.not.found');
        return;
    }
    if(!title_ids) return;
    var args = {};
    if (title_ids.length == 1) {
        args.page = RDETAIL;
        args[PARAM_RID] = title_ids[0];
    } else {
        args.page = RRESULT;
	    args[PARAM_RTYPE] = RTYPE_LIST;
	    args[PARAM_RLIST] = title_ids;
    }
    location.href = buildOPACLink(args);
}



