var cnBrowseCurrent;
var cnBrowseTopCn;
var cnBrowseTopId;
var cnBrowseBottomCn;
var cnBrowseBottomId;
var MAX_CN = 9;

function cnBrowseGo(cn) { 
	cnBrowseCurrent = cn;
	var req = new Request( FETCH_CNBROWSE_TARGET, 
		'org_unit', getLocation(), 
		'depth', getDepth(), 
		'label', cn, 
		'page_size', MAX_CN );
	req.callback( cnBrowseDraw );
	req.send();
}

function cnBrowseNext() {
	var req = new Request( FETCH_CNBROWSE_NEXT, 
		'org_unit', getLocation(), 
		'depth', getDepth(), 
		'label', cnBrowseBottomCn, 
		'boundry_id', cnBrowseBottomId,
		'page_size', MAX_CN );
	req.callback( cnBrowseDraw );
	req.send();
}

function cnBrowsePrev() {
	var req = new Request( FETCH_CNBROWSE_PREV,
		'org_unit', getLocation(), 
		'depth', getDepth(), 
		'label', cnBrowseTopCn, 
		'boundry_id', cnBrowseTopId,
		'page_size', MAX_CN );
	req.callback( cnBrowseDraw );
	req.send();
}


var cnTbody;
var cnRowT;
var cnTdT;

function cnBrowseDraw( r ) {
	swapCanvas($('cn_browse'));
	var list = r.getResultObject();

	if(!cnTbody) {
		cnTbody = $('cn_tbody');
		cnRowT = $('cn_browse_row');
		cnTdT = cnRowT.removeChild($('cn_browse_td'));
		cnTbody.removeChild(cnRowT);
	}
	removeChildren(cnTbody);

	var counter = 1;
	var currentRow = cnRowT.cloneNode(true);
	cnTbody.appendChild(currentRow);

	for( var idx in list ) {
		

		var currentTd = cnTdT.cloneNode(true);
		currentRow.appendChild(currentTd);

		var td = cnTdT.cloneNode(true);
		var label	= list[idx][0];
		var lib		= list[idx][1];
		var record	= list[idx][2];
		var id		= list[idx][3];


		if( idx == 0 ) {
			cnBrowseTopCn = label;
			cnBrowseTopId = id;
		} else if( idx == MAX_CN - 1 ) {
			cnBrowseBottomCn = label;
			cnBrowseBottomId = id;
		}

		var cn_td			= $n(currentTd, 'cn_browse_cn');
		var lib_td			= $n(currentTd, 'cn_browse_lib');
		var title_td		= $n(currentTd, 'cn_browse_title');
		var author_td		= $n(currentTd, 'cn_browse_author');
		var pic_td			= $n(currentTd, 'cn_browse_pic');

		cn_td.appendChild(text(label));
		lib_td.appendChild(text(findOrgUnit(lib).name()));

		var req = new Request( FETCH_RMODS, record );
		req.request.title_td		= title_td;
		req.request.author_td	= author_td;
		req.request.pic_td		= pic_td;
		req.callback( cnBrowseDrawTitle );
		req.send();

	
		if( counter++ % 3 == 0 ) {
			counter = 1;
			currentRow = cnRowT.cloneNode(true);
			cnTbody.appendChild(currentRow);
		}
	}
}

function cnBrowseDrawTitle(r) {
	var mods = r.getResultObject();
	buildTitleDetailLink(mods, r.title_td); 
	buildSearchLink(STYPE_AUTHOR, mods.author(), r.author_td);
	r.pic_td.setAttribute("src", buildISBNSrc(cleanISBN(mods.isbn())));

	var args = {};
	args.page = RDETAIL;
	args[PARAM_OFFSET] = 0;
	args[PARAM_RID] = mods.doc_id();
	args[PARAM_MRID] = 0;
	r.pic_td.parentNode.setAttribute("href", buildOPACLink(args));
}

