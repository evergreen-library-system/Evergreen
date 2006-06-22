var cnOffset = 0;
var cnCount = 9;
var cnBrowseCN;
var cnBrowseOrg;

if( findCurrentPage() == CNBROWSE ) {
	attachEvt("common", "run", cnBrowseLoadSearch);
	attachEvt( "common", "locationUpdated", cnBrowseResubmit );
	attachEvt( "common", "depthChanged", cnBrowseResubmit );
}


function cnBrowseLoadSearch() {
	unHideMe($('cn_browse'));
	cnBrowseGo(getCallnumber(), getLocation(), getDepth());
}


function cnBrowseResubmit() {
	var args = {}
	args[PARAM_CN] = cnBrowseCN;
	args[PARAM_DEPTH] = depthSelGetDepth();
	args[PARAM_LOCATION] = getNewSearchLocation();
	goTo(buildOPACLink(args));
}



function cnBrowseGo(cn, org, depth) { 
	if(depth == null) depth = getDepth();

	org = findOrgUnit(org);

	do {
		var t = findOrgType(org.ou_type());
		if( t.depth() > depth ) 
			org = findOrgUnit(org.parent_ou());
		else break;
	} while(true); 

	cnBrowseOrg = org;
	cnBrowseCN = cn;

	_cnBrowseGo( cn, org );
	appendClear($('cn_browse_where'), text(org.name()));
}


function _cnBrowseGo( cn, org ) {
	var req = new Request( FETCH_CNBROWSE, cn, org.id(), cnCount, cnOffset );
	req.callback( cnBrowseDraw );
	req.send();
}

function cnBrowseNext() {
	cnOffset++;
	_cnBrowseGo( cnBrowseCN, cnBrowseOrg );
}

function cnBrowsePrev() {
	cnOffset--;
	_cnBrowseGo( cnBrowseCN, cnBrowseOrg );
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

		var obj	= list[idx];
		var cn	= obj.cn;
		var mods = obj.mods;

		var cn_td			= $n(currentTd, 'cn_browse_cn');
		var lib_td			= $n(currentTd, 'cn_browse_lib');
		var title_td		= $n(currentTd, 'cn_browse_title');
		var author_td		= $n(currentTd, 'cn_browse_author');
		var pic_td			= $n(currentTd, 'cn_browse_pic');

		cn_td.appendChild(text(cn.label()));
		lib_td.appendChild(text(findOrgUnit(cn.owning_lib()).name()));
		cnBrowseDrawTitle(mods, title_td, author_td, pic_td);

		if( counter++ % 3 == 0 ) {
			counter = 1;
			currentRow = cnRowT.cloneNode(true);
			cnTbody.appendChild(currentRow);
		}
	}
}


function cnBrowseDrawTitle(mods, title_td, author_td, pic_td) {

	buildTitleDetailLink(mods, title_td); 
	buildSearchLink(STYPE_AUTHOR, mods.author(), author_td);
	pic_td.setAttribute("src", buildISBNSrc(cleanISBN(mods.isbn())));

	var args = {};
	args.page = RDETAIL;
	args[PARAM_OFFSET] = 0;
	args[PARAM_RID] = mods.doc_id();
	args[PARAM_MRID] = 0;
	pic_td.parentNode.setAttribute("href", buildOPACLink(args));
}

