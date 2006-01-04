var cnBrowseCurrent;
var cnBrowseTopCn;
var cnBrowseTopId;
var cnBrowseBottomCn;
var cnBrowseBottomId;
var cnBrowseDepth;
var cnBrowseCache = {};
var cnBrowseShowNext = false;
var cnBrowseShowPrev = false;
var MAX_CN = 9;

function cnBrowseGo(cn, depth) { 
	if(depth == null) depth = getDepth();
	cnBrowseDepth = depth;
	cnBrowseCurrent = cn;
	var req = new Request( FETCH_CNBROWSE_TARGET, 
		'org_unit', getLocation(), 
		'depth', cnBrowseDepth, 
		'label', cnBrowseCurrent,
		'page_size', MAX_CN );
	req.callback( cnBrowseDraw );
	req.send();
}

function cnBrowseNext() {
	cnBrowseShowNext = true;
	if( cnBrowseCache.next )  /* if we have it, show it */
		cnBrowseClearNext(cnBrowseCache.next);
}

function cnBrowsePrev() {
	cnBrowseShowPrev = true;
	if( cnBrowseCache.prev ) 
		cnBrowseClearPrev(cnBrowseCache.prev);
}

function cnBrowseGrabNext() {
	var req = new Request( FETCH_CNBROWSE_NEXT, 
		'org_unit', getLocation(), 
		'depth', cnBrowseDepth,
		'label', cnBrowseBottomCn, 
		'boundry_id', cnBrowseBottomId,
		'page_size', MAX_CN );
	req.callback( cnBrowseCacheMe );
	req.request.next = true;
	req.send();
}


function cnBrowseGrabPrev() {
	var req = new Request( FETCH_CNBROWSE_PREV,
		'org_unit', getLocation(), 
		'depth', cnBrowseDepth,
		'label', cnBrowseTopCn, 
		'boundry_id', cnBrowseTopId,
		'page_size', MAX_CN );
	req.callback( cnBrowseCacheMe );
	req.request.prev = true;
	req.send();
}

function cnBrowseClearNext(list) {
	cnBrowseCache.next = null; 
	cnBrowseShowNext = false;
	_cnBrowseDraw(list);
}

function cnBrowseClearPrev(list) {
	cnBrowseCache.prev = null; 
	cnBrowseShowPrev = false;
	_cnBrowseDraw(list);
}

/* cache next and previous calls unless they are 
needed immediately */
function cnBrowseCacheMe(r) {
	var list = r.getResultObject();
	if( r.next ) {
		cnBrowseCache.next = list;
		if( cnBrowseShowNext ) {
			cnBrowseClearNext(list);
		} 

	} else if( r.prev ) {
		cnBrowseCache.prev = list;
		if( cnBrowseShowPrev )  {
			cnBrowseClearPrev(list);
		} 
	}
}


function cnBrowseDraw( r ) {
	var list = r.getResultObject();
	_cnBrowseDraw(list);
}


var cnTbody;
var cnRowT;
var cnTdT;
function _cnBrowseDraw( list ) {

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

		/*
		if( label != cnBrowseCurrent ) {
			removeCSSClass( td, 'cn_browse_home_cn' );
		}
		*/

		if( idx == 0 ) { cnBrowseTopCn = label; cnBrowseTopId = id; } 
		cnBrowseBottomCn = label;
		cnBrowseBottomId = id;

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
	cnBrowseGrabNext();
	cnBrowseGrabPrev();
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

