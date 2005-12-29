
/* captures extraneous info from each record */

var subjectCache = {};
var authorCache = {};
var seriesCache = {};

function resultBuildCaches(records) {
	for( var r in records ) {
		var rec = records[r];
		for( var s in rec.subject() ) 
			subjectCache[s] == null ? subjectCache[s] = 1 : subjectCache[s]++;
		authorCache[rec.author()] = 1;
		for( var s in rec.series() ) seriesCache[rec.series()[s]] = 1;
	}
}

function resultSortSubjects(a, b) { return -(a.count - b.count); } /* sort in reverse */
function resultDrawSubjects() {

	var subjs = [];
	for( var s in subjectCache )
		subjs.push( { sub : s, count : subjectCache[s] } );
	subjs.sort(resultSortSubjects);

	var ss = [];
	for( var s in subjs ) ss.push(subjs[s].sub);

	resultDrawSidebarTrees( 
		STYPE_SUBJECT, 
		"subjectSidebarTree", ss, 
		$("subject_tree_sidebar"), 
		$("subject_sidebar_tree_div") );
}

function resultDrawAuthors() {
	var auths = new Array();
	for( var s in authorCache ) auths.push(s);

	resultDrawSidebarTrees( 
		STYPE_AUTHOR, 
		"authorSidebarTree", auths.sort(), 
		$("author_tree_sidebar"), 
		$("author_sidebar_tree_div") );
}

function resultDrawSeries() {
	var sers = new Array();
	for( var s in seriesCache ) sers.push(s);
	resultDrawSidebarTrees( 
		STYPE_SERIES, 
		"seriesSidebarTree", sers.sort(), 
		$("series_tree_sidebar"), 
		$("series_sidebar_tree_div") );
}

var IESux = true;

function resultDrawSidebarTrees( stype, treeName, items, wrapperNode, destNode ) {
	eval("tree = " + treeName);

	var xrefCache = [];
	var found = false;
	var x = 0;
	for( var i in items ) {

		if(isNull(items[i])) continue;

		/* again, IE is a turd */
		//if(IE) { if(x++ > 5) break; }
		//else { if(x++ > 7) break; }
		if(x++ > 7) break;

		found = true;

		var item = normalize(truncate(items[i], 65));
		var trunc = 65;
		var args = {};
		var href = resultQuickLink( items[i], stype );
		tree.addNode( stype + "_" + items[i], treeName + 'Root', item, href );

		if( !IE ) resultFireXRefReq(treeName, stype, items[i]);

		var a = {};
		a.type = stype;
		a.term = item;
		xrefCache.push(a);
	}

	if(found) {
		unHideMe(wrapperNode);
		if(IE) resultFireXRefSingle(treeName, xrefCache, stype);
	}
}

/*
function resultFireXRefBatch(treeName, xrefCache, stype) {
	var query = [];
	for( var i = 0; i != xrefCache.length; i++ ) {
		var topic = xrefCache[i];
		query.push( [ topic.type, topic.term ] );
	}
	var req = new Request(FETCH_CROSSREF_BATCH, query);
	var tree;
	eval('tree=' + treeName);
	req.request._tree = tree;
	req.request._stype = stype;
	req.callback(resultRenderXRefTree);
	req.send();
}
*/

var xrefCacheIndex = {};
xrefCacheIndex['subject'] = 0;
xrefCacheIndex['author'] = 0;
xrefCacheIndex['series'] = 0;

function resultHandleXRefResponse(r) {
	resultFireXRefSingle( r._treename, r._cache, r._stype );
	resultAppendCrossRef(r);
}


function resultFireXRefSingle( treeName, xrefCache, stype ) {
	var i = xrefCacheIndex[stype]++;
	if(xrefCache[i] == null) return;
	var item = xrefCache[i].term;
	var tree;
	eval('tree=' + treeName);
	var req = new Request(FETCH_CROSSREF, stype, item);
	req.request._tree = tree;
	req.request._item = item;
	req.request._stype = stype;
	req.request._cache = xrefCache;
	req.request._treename = treeName;
	req.callback(resultHandleXRefResponse);
	req.send();
}

function resultFireXRefReq( treeName, stype, item ) {
	var tree;
	eval('tree=' + treeName);
	var req = new Request(FETCH_CROSSREF, stype, item);
	req.request._tree = tree;
	req.request._item = item;
	req.request._stype = stype;
	req.callback(resultAppendCrossRef);
	req.send();
}


function resultQuickLink( term, type ) {
	var args = {};
	args.page = MRESULT;
	args[PARAM_OFFSET] = 0;
	args[PARAM_TERM] = term;
	args[PARAM_STYPE] = type;
	return buildOPACLink(args);
}

/*
function resultRenderXRefTree(r) {
	var tree = r._tree;
	var res = r.getResultObject();
	var stype = r._stype;

	for( var c in res ) {
		var cls = res[c];
		for( var t in cls ) {
			var term = res[c][t];
			var froms = term['from'];
			var alsos = term['also'];
			var total = 0;

			for( var i = 0; (total++ < 5 && i < froms.length); i++ ) {
				var string = normalize(truncate(froms[i], 45));
				if($(stype + '_' + froms[i])) continue;
				tree.addNode(stype + '_' + froms[i], 
					stype + '_' + t, string, resultQuickLink(froms[i],stype));
			}
			for( var i = 0; (total++ < 10 && i < alsos.length); i++ ) {
				var string = normalize(truncate(alsos[i], 45));
				if($(stype + '_' + alsos[i])) continue;
				tree.addNode(stype + '_' + alsos[i], 
					stype + '_' + t, string, resultQuickLink(alsos[i],stype));
			}
		}
	}
}
*/


function resultAppendCrossRef(r) {
	var tree		= r._tree
	var item		= r._item
	var stype	= r._stype;
	var result	= r.getResultObject();
	if(!result) return;
	var froms	= result['from'];
	var alsos	= result['also'];

	var total = 0;

	for( var i = 0; (total++ < 5 && i < froms.length); i++ ) {
		var string = normalize(truncate(froms[i], 45));
		if($(stype + '_' + froms[i])) continue;
		tree.addNode(stype + '_' + froms[i], 
			stype + '_' + item, string, resultQuickLink(froms[i],stype));
	}
	for( var i = 0; (total++ < 10 && i < alsos.length); i++ ) {
		var string = normalize(truncate(alsos[i], 45));
		if($(stype + '_' + alsos[i])) continue;
		tree.addNode(stype + '_' + alsos[i], 
			stype + '_' + item, string, resultQuickLink(alsos[i],stype));
	}
}





