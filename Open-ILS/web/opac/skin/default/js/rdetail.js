
/* */

detachAllEvt('common', 'run');
attachEvt("common", "run", rdetailDraw);
attachEvt("rdetail", "recordDrawn", rdetailBuildStatusColumns);
attachEvt("rdetail", "recordDrawn", rdetailBuildInfoRows);
attachEvt("rdetail", "recordDrawn", rdetailGetPageIds);

/* Per-skin configuration settings */
var rdetailLocalOnly = true;
var rdetailShowLocal = true;
var rdetailShowCopyLocation = true;
var rdetailGoogleBookPreview = true;
var rdetailDisplaySerialHoldings = true;
var rdetailEnableRefWorks = false;
var rdetailRefWorksHost = 'http://www.refworks.com';

/* vars vars vars */
var record = null;
var cp_statuses = null;
var recordsCache = [];

var copyRowParent = null;
var copyRow = null;
var statusRow = null;
var numStatuses = null;
var defaultCN;
var callnumberCache = {};
var globalCNCache = {};
var localTOC;
var cachedRecords;
var _statusPositions = {};
var opac_strings;

var nextContainerIndex;

var nextRecord;
var prevRecord;

var rdetailPrev = null;
var rdetailNext = null;
var rdetailStart = null;
var rdetailEnd = null;
var rdetailBackToResults = null;

var mfhdDetails = [];
var orgHiding = false;

if(location.href.match(/&place_hold=1/) || location.href.match(/&show_login=1/)) {
    // prevent load flicker between canvases
    hideMe(dojo.byId('canvas_main'));
}

dojo.require("dijit.Dialog");
dojo.require("dijit.form.TextBox");

/* serials are currently the only use of Dojo strings in the OPAC */
if (rdetailDisplaySerialHoldings) {
	dojo.require("dijit.Menu");
	dojo.require("dijit.form.Button");
	dojo.requireLocalization("openils.opac", "opac");
	opac_strings = dojo.i18n.getLocalization("openils.opac", "opac");
}

function rdetailReload() {
	var args = {};
	args[PARAM_LOCATION] = getNewSearchLocation();
	args[PARAM_DEPTH] = depthSelGetDepth();
	goTo(buildOPACLink(args));
}

/* looks to see if we have a next and/or previous record in the
   record cache, if so, set up the nav links */
function rdetailSetPaging(ids) {

	cachedRecords = {};
	cachedRecords.ids = ids;

	for( var i = 0; i < cachedRecords.ids.length; i++ ) {
		var rec = cachedRecords.ids[i];
		if( rec == getRid() ) {
			if( i > 0 ) prevRecord = cachedRecords.ids[i-1];
			if( i < cachedRecords.ids.length - 1 )
				nextRecord = cachedRecords.ids[i+1];
			break;
		}
	}
	var cgi = new CGI();   // add the offset if we're not on the first page of results
	var offset = parseInt(cgi.param('o'));
	if (offset)
		i = i + offset;

	$('np_offset').appendChild(text(i + 1));
	$('np_count').appendChild(text(getHitCount()));

	if(prevRecord) {
		unHideMe($('np_table'));
		unHideMe($('np_prev'));
		unHideMe($('np_start'));
		rdetailPrev = function() { _rdetailNav(prevRecord); };
		rdetailStart = function() { _rdetailNav(cachedRecords.ids[0]); };
	}

	if(nextRecord) {
		unHideMe($('np_table'));
		unHideMe($('np_next'));
		unHideMe($('np_end'));
		rdetailNext = function() { _rdetailNav(nextRecord); };
		rdetailEnd = function() { _rdetailNav(cachedRecords.ids[cachedRecords.ids.length-1]); };
	}
    rdetailBackToResults = function() { location.href = prevRResults(); };

	runEvt('rdetail', 'nextPrevDrawn', i, cachedRecords.ids.length);
}


function _rdetailNav(id, offset) {
	var args = {};
	args[PARAM_RID] = id;
	goTo(buildOPACLink(args));
}

function rdetailHandlePlaceHold() {
    function reload() {
        location.href = location.href.replace(/&place_hold=1/, '');
    }
    attachEvt("common", "holdUpdated", reload);
    attachEvt("common", "holdUpdateCanceled", reload);
    attachEvt("common", "loginCanceled", reload);
    holdsDrawEditor({record:getRid(), type: 'T'});
}

function rdetailDraw() {

    if(new CGI().param('place_hold')) {
        rdetailHandlePlaceHold();
        return;
    }

	detachAllEvt('common','depthChanged');
	detachAllEvt('common','locationUpdated');
	attachEvt('common','depthChanged', rdetailReload);
	attachEvt('common','locationUpdated', rdetailReload);
	attachEvt('common','holdUpdated', rdetailReload);
	attachEvt('common','holdUpdateCanceled', rdetailReload);

	copyRowParent = G.ui.rdetail.cp_info_row.parentNode;
	copyRow = copyRowParent.removeChild(G.ui.rdetail.cp_info_row);
	statusRow = G.ui.rdetail.cp_status.parentNode;
	statusRow.id = '__rdsrow';

	G.ui.rdetail.cp_info_local.onclick = rdetailShowLocalCopies;
	G.ui.rdetail.cp_info_all.onclick = rdetailShowAllCopies;

	if(getLocation() == globalOrgTree.id())
		hideMe(G.ui.rdetail.cp_info_all);

    if(getRid()) {

	    var req = new Request(FETCH_RMODS, getRid());
	    req.callback(_rdetailDraw);
	    req.send();

    } else { // No record ID was specified

       // If we have an ISBN in the URL, let's try to find that record
       // This allows direct linking by ISBN.
       // Note, this uses the first record it finds
       if(getRtype() == RTYPE_ISBN) { 
            var req = new Request(FETCH_ADV_ISBN_RIDS, getAdvTerm() );
            req.callback(
                function(r) {
                    var blob = r.getResultObject();
                    if(blob && blob.count > 0) 
                        RID = blob.ids[0]; 
                    var req2 = new Request(FETCH_RMODS, getRid());
                    req2.callback(_rdetailDraw);
                    req2.send();
                }
            );
            req.send();
        }
    }


	if (rdetailDisplaySerialHoldings && (
        isXUL() || !fetchOrgSettingDefault(
            getLocation(), "opac.fully_compressed_serial_holdings")
        )
    ) {
		var req = new Request(FETCH_MFHD_SUMMARY, getRid());
		req.callback(_holdingsDraw);
		req.send();
		if (isXUL()) {
			var here = findOrgUnit(getLocation());
			dojo.place("<div id='mfhd_ad_menu'></div>", "rdetail_details_table", "after");
			var mfhd_add = new dijit.Menu({style:"float: right;"});
			new dijit.MenuItem({onClick:function(){
				var bibReq = new Request(FETCH_BRE, [getRid()]);
				bibReq.send(true);
				var bib = bibReq.result()[0];
				var sourceReq = new Request(FETCH_BIB_SOURCE, G.user.session, bib.source());
				sourceReq.send(true);
				var source = sourceReq.result();
				if (source && source.can_have_copies() == 'f') {
					alert(dojo.string.substitute(opac_strings.SOURCE_CANNOT_HAVE_COPIES, [source.source()]));
				} else {
					var req = new Request(CREATE_MFHD_RECORD, G.user.session, 1, here.id(), getRid());
					var res = req.send();
					alert(dojo.string.substitute(opac_strings.CREATED_MFHD_RECORD, [here.name()]));
				}
			}, label:opac_strings.CREATE_MFHD}).placeAt(mfhd_add);
			mfhd_add.placeAt(mfhd_ad_menu);
		}
	}

	detachAllEvt("result", "idsReceived");
	G.evt.result.hitCountReceived = [];
	G.evt.result.recordReceived = [];
	G.evt.result.copyCountsReceived = [];
	G.evt.result.allRecordsReceived = [];

    if(isXUL()) 
        unHideMe($('rdetail_show_orders'));
}

function rdetailGetPageIds() {
	attachEvt("result", "idsReceived", rdetailSetPaging );
	resultFetchAllRecords = true;
	rresultCollectIds(true);
}


function buildunAPISpan (span, type, id) {
	var cgi = new CGI();
	var d = new Date();

	addCSSClass(span,'unapi-id');

	span.setAttribute(
			'title', 'tag:' + cgi.server_name + ',' +
			d.getFullYear() + ':' + type + '/' + id
			);
}

function rdetailViewMarc(r,id) {
	hideMe($('rdetail_extras_loading'));
	$('rdetail_view_marc_box').innerHTML = r.getResultObject();

	var div = elem('div', { "class" : 'hide_me' });
	var span = div.appendChild( elem('abbr') );

	buildunAPISpan( span, 'biblio-record_entry', record.doc_id() );

	$('rdetail_view_marc_box').insertBefore(span, $('rdetail_view_marc_box').firstChild);
}

function rdetailForeignItems(r,id) {
	hideMe($('rdetail_extras_loading'));
    var tbody = $('rdetail_foreign_items_tbody');

    var robj = r.getResultObject(); /* mvr list with foreign_copy_maps fleshed */

    for (var i = 0; i < robj.length; i++) {
        var args = {};
        args.page = RDETAIL;
        args[PARAM_OFFSET] = 0;
        args[PARAM_RID] = robj[i].doc_id();
        var row = elem('tr'); tbody.appendChild(row);
        var td1 = elem('td'); row.appendChild(td1);
        var title = elem(
            'a',
            {
                'href' : buildOPACLink(args),
                'class' : 'classic_link'
            },
            robj[i].title()
        );
        td1.appendChild(title);
        var td2 = elem('td',{},robj[i].author()); row.appendChild(td2);
        var td3 = elem('td'); row.appendChild(td3);
        var details = elem(
            'a',
            {
                'href' : 'javascript:void(0)',
                'class' : 'classic_link'
            },
            'Copy Details'
        );
        details.onclick = function(idx,context_row){
            return function() {
                cpdBuild(
                    tbody,
                    context_row,
                    robj[idx],
                    null,
                    1,
                    0,
                    1,
                    dojo.map(
                        robj[idx].foreign_copy_maps(),
                        function(x){ return x.target_copy(); }
                    ),
                    dojo.map(
                        robj[idx].foreign_copy_maps(),
                        function(x){ return x.peer_type().name(); }
                    )
                );
            };
        }(i,row);
        td3.appendChild(details);
    }
}



function rdetailShowLocalCopies() {
	rdetailShowLocal = true;
	rdetailBuildInfoRows();
	hideMe(G.ui.rdetail.cp_info_local);
	unHideMe(G.ui.rdetail.cp_info_all);
	hideMe(G.ui.rdetail.cp_info_none); 
}

function rdetailShowAllCopies() {

	rdetailShowLocal = false;
	rdetailBuildInfoRows();
	hideMe(G.ui.rdetail.cp_info_all);
	unHideMe(G.ui.rdetail.cp_info_local);
	hideMe(G.ui.rdetail.cp_info_none); 
}

function OpenMarcEditWindow(pcrud, rec) {
	/*
	   To run in Firefox directly, must set signed.applets.codebase_principal_support
	   to true in about:config
	 */
	win = window.open('/xul/server/cat/marcedit.xul','','chrome'); // XXX version?
	dojo.require('openils.PermaCrud');

	win.xulG = {
		"record": {"marc": rec.marc(), "rtype": "sre"},
		"save": {
			"label": opac_strings.SAVE_MFHD_LABEL,
			"func": function(xmlString) {
				rec.marc(xmlString);
				rec.edit_date('now');
				rec.ischanged(true);
				pcrud.update(rec);
			}
		},
        'lock_tab' : typeof xulG != 'undefined' ? (typeof xulG['lock_tab'] != 'undefined' ? xulG.lock_tab : undefined) : undefined,
        'unlock_tab' : typeof xulG != 'undefined' ? (typeof xulG['unlock_tab'] != 'undefined' ? xulG.unlock_tab : undefined) : undefined
	};
}

function loadMarcEditor(recId) {
	var pcrud = new openils.PermaCrud({"authtoken": G.user.session});
	var rec = pcrud.retrieve("sre", recId);
	if (rec) {
		OpenMarcEditWindow(pcrud, rec);
	}
}

/*
 * This function could be written much more intelligently
 * Limited brain power means that I'm brute-forcing it for now
 */
function _holdingsDraw(h) {
    holdings = h.getResultObject();

    if (holdings) {
        // Only draw holdings within our OU scope
        var here = findOrgUnit(getLocation());
        var entryNum = 0;
        var depth = getDepth();
        dojo.forEach(holdings, function (item) {
            if (orgIsMine(here, findOrgUnit(item.owning_lib()), depth)) {
                _holdingsDrawMFHD(item, entryNum);
                entryNum++;
            }
        });
    }

    // Populate (or unpopulate) XUL menus
    if (isXUL()) {
        runEvt('rdetail','MFHDDrawn');
    }
}

function _holdingsDrawMFHD(holdings, entryNum) {
	var hb = holdings.basic_holdings();
	var hba = holdings.basic_holdings_add();
	var hs = holdings.supplement_holdings();
	var hsa = holdings.supplement_holdings_add();
	var hi = holdings.index_holdings();
	var hia = holdings.index_holdings_add();
	var ho = holdings.online();
	var hm = holdings.missing();
	var hinc = holdings.incomplete();
	var hloc = holdings.location() || 'MFHD';

	if (	hb.length == 0 && hba.length == 0 && hs.length == 0 &&
		hsa.length == 0 && hi.length == 0 && hia.length == 0 &&
		ho.length == 0 && hm.length == 0 && hinc.length == 0
	) {

		if (isXUL()) {
			/* 
			 * If we have a record, but nothing to show for it, then the
			 * record is likely empty or corrupt. This gives cataloguers a
			 * chance to add holdings or correct the record
			 */
			hb = ['PLACEHOLDER'];
		} else {
			return null;
		}
	}

	// Show entryNum + 1 in staff client for better menu correlation
	// Maybe this should be holdings.sre_id() instead? (which could get long after time)
	var entryNumString = '';
	if (isXUL()) {
		var entryNumInc = entryNum + 1;
		entryNumString = ' [Entry #'+entryNumInc+'] ';
	}

	var refNode;
	if (entryNum > 0) {
		refNode = 'rdetail_holdings_table_' + (entryNum - 1);
	} else {
		refNode = 'rdetail_details_table';
	}

	dojo.place("<table style='width: 100%;' id='rdetail_holdings_table_"+entryNum+"'><caption id='mfhdHoldingsCaption" + entryNum + "' class='rdetail_header color_1'>" +
		dojo.string.substitute(opac_strings.HOLDINGS_TABLE_CAPTION, [hloc]) + entryNumString +
		"</caption><tbody id='rdetail_holdings_tbody_" + entryNum +
		"'></tbody></table>", refNode, "after"
	);
	if (hb.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.BASIC_HOLDINGS, hb); }
	if (hba.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.BASIC_HOLDINGS_ADD, hba); }
	if (hs.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.SUPPLEMENT_HOLDINGS, hs); }
	if (hsa.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.SUPPLEMENT_HOLDINGS_ADD, hsa); }
	if (hi.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.INDEX_HOLDINGS, hi); }
	if (hia.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.INDEX_HOLDINGS_ADD, hia); }
	if (ho.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.ONLINE_VOLUMES, ho); }
	if (hm.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.MISSING_VOLUMES, hm); }
	if (hinc.length > 0) { _holdingsDrawMFHDEntry(entryNum, opac_strings.INCOMPLETE_VOLUMES, hinc); }

	if (isXUL() && holdings.sre_id() != -1) { // -1 indicates in-DB only holdings, so no button or menu entries for MFHD
		mfhdDetails.push({ 'id' : holdings.sre_id(), 'label' : hloc, 'entryNum' : entryNum, 'owning_lib' : holdings.owning_lib() });
		dojo.require('openils.Event');
		dojo.require('openils.PermaCrud');
		var mfhd_edit = new dijit.Menu({});
		new dijit.MenuItem({onClick: function(){loadMarcEditor(holdings.sre_id())}, label:opac_strings.EDIT_MFHD_RECORD}).placeAt(mfhd_edit, "first");
		new dijit.MenuItem({onClick:function(){
			// Avoid accidental deletion of MFHD records
			if (!confirm(opac_strings.DELETE_MFHD_CONFIRM)) {
				return;
			}
			var pcrud = new openils.PermaCrud({"authtoken": G.user.session});
			var mfhd_rec = pcrud.retrieve("sre", holdings.sre_id());
			if (mfhd_rec) {
				pcrud.eliminate(mfhd_rec);
				alert(dojo.string.substitute(opac_strings.DELETED_MFHD_RECORD, [holdings.sre_id()]));
			}
		}, label:opac_strings.DELETE_MFHD}).placeAt(mfhd_edit, "last");
		// new dijit.MenuItem({onClick:function(){alert("Edit properties " + holdings.sre_id());}, label:opac_strings.EDIT_PROPERTIES}).placeAt(mfhd_edit, "last");
		var mfhd_mb = new dijit.form.DropDownButton({dropDown: mfhd_edit, label:opac_strings.EDIT_MFHD_MENU, style:"float:right"});
		mfhd_mb.placeAt("mfhdHoldingsCaption" + entryNum, "last");
		mfhd_edit.startup();
	}
}

function _holdingsDrawMFHDEntry(entryNum, entryName, entry) {
	var flatEntry = entry.toString().replace(/,/g, ', ');
	dojo.place("<tr><td> </td><td nowrap='nowrap' class='rdetail_desc'>" + entryName + "</td><td class='rdetail_item'>" + flatEntry + "</td></tr>", "rdetail_holdings_tbody_" + entryNum, "last");
}

function _rdetailDraw(r) {
	record = r.getResultObject();

	runEvt('rdetail', 'recordRetrieved', record.doc_id());

	G.ui.rdetail.title.appendChild(text(record.title()));
	buildSearchLink(STYPE_AUTHOR, record.author(), G.ui.rdetail.author);
	G.ui.rdetail.isbn.appendChild(text(cleanISBN(record.isbn())));
	G.ui.rdetail.edition.appendChild(text(record.edition()));
	G.ui.rdetail.pubdate.appendChild(text(record.pubdate()));
	G.ui.rdetail.publisher.appendChild(text(record.publisher()));
	$('rdetail_physical_desc').appendChild(text(record.physical_description()));
	r = record.types_of_resource();
	if(r) {
		G.ui.rdetail.tor.appendChild(text(r[0]));
		setResourcePic( G.ui.rdetail.tor_pic, r[0]);
	}
	G.ui.rdetail.abstr.appendChild(text(record.synopsis()));

	try{
		if(record.isbn()) {
			if(ENABLE_ADDED_CONTENT_ATTRIB_LINKS) {
				unHideMe($('rdetail.jacket_attrib_div'));
				var href = $('rdetail.jacket_attrib_link').getAttribute('href') +cleanISBN(record.isbn());
				$('rdetail.jacket_attrib_link').setAttribute('href', href);
			}
			rdetailCheckForGBPreview();

		} else {
			hideMe($("rdetail.jacket_attrib_div"));
			hideMe($("rdetail_img_link"));
		}
	} catch(E) {}


	// see if the record has any external links 
	var links = record.online_loc();
	for( var i = 0; links && links.length > 0 && i < links.length; i = i + 3 ) {
		var href = links[i];
		// avoid matching "HTTP: The Complete Reference"
		if( href.match(/https?:\/|ftps?:\/|mailto:/i) ) {
			unHideMe($('rdetail_online_row'));
			// MODS can contain a display label (used for the text of the link)
			// as well as a note about the URL; many legacy systems conflate the
			// two and generate MARC records that expect the note to be used as
			// the text of the link, with no display label; here's the canonical
			// format:
			//
			// 856 40 $uhttp://localhost$yDisplay label$zPublic note
			//
			// Note that the MARC21slim2MODS XSL concatenates $3 and $y together
			// (as $y was defined later in MARC21's life as the display label)
			var displayLabel = '' + links[i+1];
			var note = '' + links[i+2];
			if(!displayLabel || displayLabel.match(/https?:\/|ftps?:\/|mailto:/i)) {
				if(!note || note.match(/https?:\/|ftps?:\/|mailto:/i)) {
					displayLabel = href;
				} else {
					displayLabel = note;
				}
			}
			$('rdetail_online').appendChild(elem('a', {href:href,'class':'classic_link'}, displayLabel));
			if (note && note != displayLabel) {
				$('rdetail_online').appendChild(elem('span', {'class':'url_note'}, ' - ' + note));
			}
			$('rdetail_online').appendChild(elem('br'));
		}
	}

	// Fill in our unAPI ID, if anyone cares
	var abbrs = document.getElementsByTagName('abbr');
	var span;
	for (var i = 0; i < abbrs.length; i++) {
		if (abbrs[i].getAttribute('name') == 'unapi') {
			span = abbrs[i];
			break;
		}
	}
	buildunAPISpan( span, 'biblio-record_entry', record.doc_id() );

	$('rdetail_place_hold').onclick = function() {
        var src = location.href;

        if(forceLoginSSL && src.match(/^http:/)) {

            src = src.replace(/^http:/, 'https:');

            if(!src.match(/&place_hold=1/)) {
                src += '&place_hold=1';
            }

            location.href = src;

        } else {
            holdsDrawEditor({record:record.doc_id(), type:'T'});
        }
    }


	var RW = $('rdetail_exp_refworks');
	if (RW && rdetailEnableRefWorks) {

		var here = (findOrgUnit(getLocation())).name();
		var org_name = here.replace(" ", "+");
		var cgi = new CGI();

		RW.setAttribute(
			'href',
			rdetailRefWorksHost + '/express/expressimport.asp?vendor='
			+ org_name
			+ '&filter=MARC+Format&database=All+MARC+Formats&encoding=65001&url=http%3A%2F%2F'
			+ cgi.server_name + '/opac/extras/supercat/marctxt/record/'
			+ record.doc_id()
	       );

		RW.setAttribute('target', 'RefWorksMain');

		unHideMe($('rdetail_exp_refworks_span'));
	}

	$('rdetail_img_link').setAttribute('href', buildISBNSrc(cleanISBN(record.isbn()), 'large'));
	G.ui.rdetail.image.setAttribute("src", buildISBNSrc(cleanISBN(record.isbn())));
	runEvt("rdetail", "recordDrawn");
	recordsCache.push(record);

	rdetailSetExtrasSelector();

	var breq = new Request(FETCH_BRE, [getRid()]);
	breq.callback( rdetailCheckDeleted );
	breq.send();

	//resultBuildCaches( [ record ] );
	//resultDrawSubjects();
	//resultDrawSeries();

	// grab added content 

    // Proxied through Evergreen AddedContent module
	acCollectData(cleanISBN(record.isbn()), rdetailhandleAC);

    var currentISBN = cleanISBN(record.isbn());

    // Not proxied, cross-site javascript

    // ChiliFresh
    if (chilifresh && chilifresh != '(none)' && currentISBN) {
        $('chilifreshReviewLink').setAttribute('id','isbn_'+currentISBN);
        $('chilifreshReviewResult').setAttribute('id','chili_review_'+currentISBN);
        unHideMe($('rdetail_reviews_link'));
        unHideMe($('rdetail_chilifresh_reviews'));
        try {
            chili_init();
        } catch(E) {
            console.log(E + '\n');
            hideMe($('rdetail_reviews_link'));
            hideMe($('rdetail_chilifresh_reviews'));
        }
    }

    // Novelist
    if (novelist && currentISBN) {
        unHideMe($('rdetail_novelist_link'));
    }

    // Multi-Home / Foreign Items / Peer Bibs
    var req = new Request( TEST_PEER_BIBS, record.doc_id() );
    req.callback(function(r){
        var test = r.getResultObject();
        if (test == "1") {
            unHideMe($('rdetail_foreign_items_link'));
        }
    }); 
    req.send();
}



function rdetailCheckDeleted(r) {
	var br = r.getResultObject()[0];
	if( isTrue(br.deleted()) ) {
		hideMe($('rdetail_place_hold'));
		$('rdetail_more_actions_selector').disabled = true;
		unHideMe($('rdetail_deleted_exp'));
	}
}

function rdetailSetExtrasSelector() {
	if(!grabUser()) return;
	unHideMe($('rdetail_more_actions'));

	var req = new Request( 
			FETCH_CONTAINERS, G.user.session, G.user.id(), 'biblio', 'bookbag' );
	req.callback(rdetailAddBookbags);
	req.send();
}

function rdetailAddBookbags(r) {

	var containers = r.getResultObject();
	var selector = $('rdetail_more_actions_selector');
	var found = false;
	var index = 3;
	doSelectorActions(selector);

	for( var i = 0; i < containers.length; i++ ) {
		found = true;
		var container = containers[i];
		insertSelectorVal( selector, index++, container.name(), 
				"container_" + container.id(), rdetailAddToBookbag,  1 );
	}

	nextContainerIndex = index;
}

var _actions = {};
/**
 * Adds a new bookbag and exits.
 * 
 * exitstatus should be 0 if the status is to be read.
 */
function finishBookbag(exitstatus) {
	var name = bbName.attr('value');
	
	newBBDialog.hide();	
	bbName.attr("value", ""); // Do this after hide so the text doesn't disappear.
	
	if(exitstatus != 0) return; // If the user canceled, just drop off here.
	
	var id;
	
	if( id = containerCreate( name ) ) {
		alert( $('rdetail_bb_success').innerHTML );
		var selector = $('rdetail_more_actions_selector');
		insertSelectorVal( selector, nextContainerIndex++, name, 
				"container_" + id, rdetailAddToBookbag, 1 );
		setSelector( selector, 'start' );
	}
}

/**
 * Creates a new Bookbag for the user.
 */
function rdetailNewBookbag() {
    newBBDialog.show(); // Show the bookbag dialog.
    dojo.connect(dijit.byId('newBBDialog'), 'onKeyPress', function(evt) {
        if (evt.keyCode == dojo.keys.ENTER) {
            finishBookbag(0);
        }
    });
}

function rdetailAddToBookbag() {
	var selector = $('rdetail_more_actions_selector');
	var id = selector.options[selector.selectedIndex].value;
	setSelector( selector, 'start' );

	if( containerCreateItem( id.substring(10), record.doc_id() )) {
		alert($('rdetail_bb_item_success').innerHTML);
	}
}


var rdetailMarcFetched = false;
var rdetailForeignItemsFetched = false;
function rdetailShowExtra(type, args) {

	hideMe($('rdetail_copy_info_div'));
	hideMe($('rdetail_summary_div'));
	hideMe($('rdetail_reviews_div'));
	hideMe($('rdetail_toc_div'));
	hideMe($('rdetail_anotes_div'));
	hideMe($('rdetail_excerpt_div'));
	hideMe($('rdetail_preview_div'));
	hideMe($('rdetail_marc_div'));
	hideMe($('cn_browse'));
	hideMe($('rdetail_cn_browse_div'));
	hideMe($('rdetail_novelist_div'));
	hideMe($('rdetail_foreign_items_div'));
	hideMe($('rdetail_notes_div'));

	removeCSSClass($('rdetail_copy_info_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_viewcn_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_summary_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_reviews_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_toc_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_excerpt_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_preview_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_anotes_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_annotation_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_viewmarc_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_novelist_link'), 'rdetail_extras_selected');
	removeCSSClass($('rdetail_foreign_items_link'), 'rdetail_extras_selected');

	switch(type) {

		case "copyinfo": 
			unHideMe($('rdetail_copy_info_div')); 
			addCSSClass($('rdetail_copy_info_link'), 'rdetail_extras_selected');
			break;

        case "summary":
            addCSSClass($('rdetail_summary_link'), 'rdetail_extras_selected');
            unHideMe($('rdetail_summary_div'));
            break;

		case "reviews": 
			addCSSClass($('rdetail_reviews_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_reviews_div')); 
			break;

		case "excerpt": 
			addCSSClass($('rdetail_excerpt_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_excerpt_div'));
			break;

		case "preview": 
			addCSSClass($('rdetail_preview_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_preview_div'));
			rdetailDisplayGBPreview();
			break;

		case "anotes": 
			addCSSClass($('rdetail_anotes_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_anotes_div'));
			break;

		case "toc": 
			addCSSClass($('rdetail_toc_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_toc_div'));
			break;

		case "marc": 
			addCSSClass($('rdetail_viewmarc_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_marc_div')); 
			if(rdetailMarcFetched) return;
			unHideMe($('rdetail_extras_loading'));
			rdetailMarcFetched = true;
			var req = new Request( FETCH_MARC_HTML, record.doc_id() );
			req.callback(rdetailViewMarc); 
			req.send();
			break;

		case "novelist": 
			addCSSClass($('rdetail_novelist_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_novelist_div')); 
			break;

		case "foreign_items": 
			addCSSClass($('rdetail_foreign_items_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_foreign_items_div')); 
            if(rdetailForeignItemsFetched) return;
			unHideMe($('rdetail_extras_loading'));
            rdetailForeignItemsFetched = true;
			var req = new Request( FETCH_PEER_BIBS, record.doc_id() );
			req.callback(rdetailForeignItems); 
			req.send();
			break;

		case 'cn':
			addCSSClass($('rdetail_viewcn_link'), 'rdetail_extras_selected');
			unHideMe($('rdetail_cn_browse_div'));
			rdetailShowCNBrowse(defaultCN[1], getLocation(), null, true);
			break;

	}
}

function rdetailVolumeDetails(args) {
	var row = $(args.rowid);
	var tbody = row.parentNode;
	cpdBuild( tbody, row, record, [args.cn_prefix, args.cn, args.cn_suffix], args.org, args.depth, args.copy_location );
	return;
}

function rdetailBuildCNList() {

	var select = $('cn_browse_selector');
	var index = 0;
	var arr = [];
	for( var cn_json in callnumberCache ) arr.push( cn_json );
	arr.sort();

	if( arr.length == 0 ) {
		hideMe($('rdetail_cn_browse_select_div'));
		return;
	}

	for( var i = 0; i < arr.length; i++ ) {
		var cn_json = arr[i];
        var cn = JSON2js(cn_json);
        var whole_cn_text = (cn[0] ? cn[0] + ' ' : '') + cn[1] + (cn[2] ? ' ' + cn[2] : '');
		var opt = new Option(whole_cn_text,cn_json);
		select.options[index++] = opt;
	}
	select.onchange = rdetailGatherCN;
}

function rdetailGatherCN() {
	var cn = getSelectorVal($('cn_browse_selector'));
	rdetailShowCNBrowse( JSON2js(cn), getLocation(), getDepth(), true );
	setSelector( $('cn_browse_selector'), cn );
}


function rdetailShowCNBrowse( cn, loc, depth, fromOnclick ) {

	if(!cn) {
		unHideMe($('cn_browse_none'));
		hideMe($('rdetail_cn_browse_select_div'));
		return;
	}

	unHideMe($('rdetail_cn_browse_select_div'));
	rdetailBuildCNList();
	setSelector( $('cn_browse_selector'), js2JSON(cn) );
	hideMe($('rdetail_copy_info_div'));
	hideMe($('rdetail_reviews_div'));
	hideMe($('rdetail_summary_div'));
	hideMe($('rdetail_toc_div'));
	hideMe($('rdetail_marc_div'));
	unHideMe($('rdetail_cn_browse_div'));
	unHideMe($('cn_browse'));
	if( !rdetailLocalOnly && ! fromOnclick ) depth = findOrgDepth(globalOrgTree);
	cnBrowseGo(cn, loc, depth);
}

function rdetailhandleAC(data) {

	if( data.summary.html ) {
		$('rdetail_summary_div').innerHTML = data.summary.html;
		unHideMe($('rdetail_summary_link'));
	}

	if( data.reviews.html ) {
		$('rdetail_review_container').innerHTML = data.reviews.html;
		unHideMe($('rdetail_reviews_link'));
	}

	if( data.toc.html ) {
		$('rdetail_toc_div').innerHTML = data.toc.html;
		unHideMe($('rdetail_toc_link'));
	}

	if( data.excerpt.html ) {
		$('rdetail_excerpt_div').innerHTML = data.excerpt.html;
		unHideMe($('rdetail_excerpt_link'));
	}

	if( data.anotes.html ) {
		$('rdetail_anotes_div').innerHTML = data.anotes.html;
		unHideMe($('rdetail_anotes_link'));
	}
}

function rdetailShowReviews(r) {
	hideMe($('rdetail_extras_loading'));
	var res = r.getResultObject();
	var par = $('rdetail_reviews_div');
	var template = par.removeChild($('rdetail_review_template'));
	if( res && res.length > 0 ) {
		unHideMe($('rdetail_reviews_link'));
		for( var i = 0; i < res.length; i++ ) {
			var rev = res[i];	
			if( rev.text && rev.info ) {
				var node = template.cloneNode(true);
				$n(node, 'review_header').appendChild(text(rev.info));
				$n(node, 'review_text').appendChild(text(rev.text));
				par.appendChild(node);
			}
		}
	}
}


function rdetailShowTOC(r) {
	hideMe($('rdetail_extras_loading'));
	var resp = r.getResultObject();
	if(resp) {
		unHideMe($('rdetail_toc_link'));
		$('rdetail_toc_div').innerHTML = resp;
	}
}

function rdetailBuildInfoRows() {
	var req;
	var method = FETCH_COPY_COUNTS_SUMMARY;
	if (rdetailShowCopyLocation)
		method = FETCH_COPY_LOCATION_COUNTS_SUMMARY;
	if( rdetailShowLocal ) 
		req = new Request(method, record.doc_id(), getLocation(), getDepth())
	else
		req = new Request(method, record.doc_id());
	req.callback(_rdetailBuildInfoRows);
	req.send();
}

function _rdetailRows(node) {

	if( rdetailShowLocal && getLocation() != globalOrgTree.id() ) {
		var loc = findOrgUnit(getLocation());
		if( node ) {
			if( !orgIsMine(node, loc) && !orgIsMine(loc,node) ) return;
		} else {
            var kids = globalOrgTree.children();
            if (kids) {
    			for( var i = 0; i < kids.length; i++ ) {
	    			var org = findOrgUnit(kids[i]);
		    		if( orgIsMine(org, loc) ) {
			    		node = org;
				    	break;
    				}
                }
			}
		} 
	}

	if(!node && findOrgType(globalOrgTree.ou_type()).can_have_vols())
		node = globalOrgTree;


	/* don't show hidden orgs */

	if(node) {

		if(!isXUL() && !isTrue(node.opac_visible())) return;

		if (orgHiding) {
			if (isTrue( findOrgType(node.ou_type()).can_have_vols() )) {
				if ( ! orgIsMine( orgHiding.org, node, orgHiding.depth ) ) {
					return;
				}
			}
		}

		var row = copyRow.cloneNode(true);
		row.id = "cp_info_" + node.id();

		var libtd = findNodeByName( row, config.names.rdetail.lib_cell );
		var cntd  = findNodeByName( row, config.names.rdetail.cn_cell );
		var cpctd = findNodeByName( row, config.names.rdetail.cp_count_cell );
		var actions = $n(row, 'rdetail_actions_cell');

		var p = libtd.getElementsByTagName('a')[0];
		libtd.insertBefore(text(node.name()), p);
		libtd.setAttribute("style", "padding-left: " + ((findOrgDepth(node) - 1)  * 9) + "px;");

		if(!findOrgType(node.ou_type()).can_have_vols()) {

			row.removeChild(cntd);
			row.removeChild(cpctd);
			row.removeChild(actions);
			row.setAttribute('novols', '1');

			libtd.setAttribute("colspan", numStatuses + 3 );
			libtd.colSpan = numStatuses + 3;
			addCSSClass(row, 'copy_info_region_row');
		} 

		copyRowParent.appendChild(row);

	} else { node = globalOrgTree; }

    var kids = node.children();
    if (kids) {
    	for( var c = 0; c < kids.length; c++ ) 
	    	_rdetailRows(kids[c]);
    }
}

function rdetailCNPrint(orgid, cn) {
	var div = cpdBuildPrintWindow( record, orgid);
	var template = div.removeChild($n(div, 'cnrow'));
	var rowNode = $("cp_info_" + orgid);
	cpdStylePopupWindow(div);
	openWindow(div.innerHTML);
}

var localCNFound = false;
var ctr = 0;
function _rdetailBuildInfoRows(r) {

	if (rdetailShowCopyLocation)
		unHideMe( $n( $('rdetail_copy_info_table'), 'rdetail_copylocation_header' ) );

	removeChildren(copyRowParent);

	orgHiding = checkOrgHiding();

	_rdetailRows();

	var summary = r.getResultObject();
	if(!summary) return;

	var found = false;
	for( var i = 0; i < summary.length; i++ ) {

		var arr = summary[i];
		globalCNCache[js2JSON([arr[1],arr[2],arr[3]])] = 1; // prefix, label, suffix.  FIXME - Am I used anywhere?
		var thisOrg = findOrgUnit(arr[0]);
		var rowNode = $("cp_info_" + thisOrg.id());
		if(!rowNode) continue;

		if(rowNode.getAttribute("used")) {

			if( rowNode.nextSibling ) {
				sib = rowNode.nextSibling;
				o ='cp_info_'+thisOrg.id()+'_';
				/* push the new row on as the last row for this org unit */
				while( sib && sib.id.match(o) ) {
					sib = sib.nextSibling;
				}
				if(sib)
					rowNode = copyRowParent.insertBefore(copyRow.cloneNode(true), sib);
				else
					rowNode = copyRowParent.appendChild(copyRow.cloneNode(true));
			} else {
				rowNode = copyRowParent.appendChild(copyRow.cloneNode(true));
			}

			var n = findNodeByName( rowNode, config.names.rdetail.lib_cell );
			n.appendChild(text(thisOrg.name()));
			n.setAttribute("style", "padding-left: " + ((findOrgDepth(thisOrg) - 1)  * 9) + "px;");
			rowNode.id = "cp_info_" + thisOrg.id() + '_' + (++ctr); 

		} else {
			rowNode.setAttribute("used", "1");
		}

		var cpc_temp = rowNode.removeChild(
				findNodeByName(rowNode, config.names.rdetail.cp_count_cell));

		var statuses = arr[4];
		var cl = '';
		if (rdetailShowCopyLocation) {
			cl = arr[4];
			statuses = arr[5];
		}


		rdetailApplyStatuses(rowNode, cpc_temp, statuses);

		var isLocal = false;
		if( orgIsMine( findOrgUnit(getLocation()), thisOrg ) ) { 
			found = true; 
			isLocal = true; 
			if(!localCNFound) {
				localCNFound = true;
				defaultCN = [arr[1],arr[2],arr[3]]; // prefix, label, suffix
			}
		}

		//if(isLocal) unHideMe(rowNode);
		unHideMe(rowNode);

		rdetailSetPath( thisOrg, isLocal );
		rdetailBuildBrowseInfo( rowNode, [arr[1],arr[2],arr[3]], isLocal, thisOrg, cl );

		if( i == summary.length - 1 && !defaultCN) defaultCN = [arr[1],arr[2],arr[3]]; // prefix, label, suffix
	}

	if(!found) unHideMe(G.ui.rdetail.cp_info_none);
}

function rdetailBuildBrowseInfo(row, cn, local, orgNode, cl) {

    var whole_cn_json = js2JSON(cn);
    var whole_cn_text = (cn[0] ? cn[0] + ' ' : '') + cn[1] + (cn[2] ? ' ' + cn[2] : '');

	if(local) {
		var cache = callnumberCache[whole_cn_json];
		if( cache ) cache.count++;
		else callnumberCache[whole_cn_json] = { count : 1 };
	}

	var depth = getDepth();
	if( !local ) depth = findOrgDepth(globalOrgTree);

	$n(row, 'rdetail_callnumber_cell').appendChild(text(whole_cn_text));

	if (rdetailShowCopyLocation) {
		var cl_cell = $n(row, 'rdetail_copylocation_cell');
		cl_cell.appendChild(text(cl));
		unHideMe(cl_cell);
	}

	_debug('setting action clicks for cn ' + whole_cn_text);

	var dHref = 'javascript:rdetailVolumeDetails('+
			'{copy_location : "'+cl.replace(/\"/g, '\\"')+'", rowid : "'+row.id+'", cn_prefix :"'+cn[0].replace(/\"/g, '\\"')+'",cn :"'+cn[1].replace(/\"/g, '\\"')+'",cn_suffix :"'+cn[2].replace(/\"/g, '\\"')+'", depth:"'+depth+'", org:"'+orgNode.id()+'", local: '+local+'});';

	var bHref = 'javascript:rdetailShowCNBrowse("'+cn[1].replace(/\"/g, '\\"') + '", '+orgNode.id()+', "'+depth+'");'; 

	unHideMe( $n(row, 'details') )
		$n(row, 'details').setAttribute('href', dHref);
	unHideMe( $n(row, 'browse') )
		$n(row, 'browse').setAttribute('href', bHref);

	if(isXUL()) {
		unHideMe($n(row, 'hold_div'));
		$n(row, 'hold').onclick = function() {
			var req = new Request(FETCH_VOLUME_BY_INFO, cn, record.doc_id(), orgNode.id());
			req.callback(
					function(r) {
					var vol = r.getResultObject();
					holdsDrawEditor({type: 'V', volumeObject : vol});
					}
				    );
			req.send();
		};
	}
}

// sets the path to org as 'active' and displays the path if it's local 
function rdetailSetPath(org, local) {
	if( findOrgDepth(org) == 0 ) return;
	var row = $("cp_info_" + org.id());
	row.setAttribute("hasinfo", "1");
	unHideMe(row);
	rdetailSetPath(findOrgUnit(org.parent_ou()), local);
}

//Append all the statuses for a given summary to the 
//copy summary table 
function rdetailApplyStatuses( row, template, statuses ) {
	for( var j in _statusPositions ) {
		var stat = _statusPositions[j];
		var val = statuses[stat.id()];
		var nn = template.cloneNode(true);
		if(val) nn.appendChild(text(val));
		else nn.appendChild(text(0));
		row.appendChild(nn);
	}
}

//Add one td (creating a new column) to the copy summary
//table for each opac_visible copy status
function rdetailBuildStatusColumns() {

	rdetailGrabCopyStatuses();
	var parent = statusRow;
	var template = parent.removeChild(G.ui.rdetail.cp_status);

	var i = 0;
	for( i = 0; i < cp_statuses.length; i++ ) {

		var c = cp_statuses[i];
		if( c && isTrue(c.opac_visible()) ) {
			var name = c.name();
			_statusPositions[i] = c;
			var node = template.cloneNode(true);
			var data = findNodeByName( node, config.names.rdetail.cp_status);

			data.appendChild(text(name));
			parent.appendChild(node);
		}
	}	

	numStatuses = 0;
	for(x in _statusPositions) numStatuses++; 
}

function rdetailGrabCopyStatuses() {
	if(cp_statuses) return cp_statuses;
	var req = new Request(FETCH_COPY_STATUSES);
	req.send(true);
	cp_statuses = req.result();
	cp_statuses = cp_statuses.sort(_rdetailSortStatuses);
}

function _rdetailSortStatuses(a, b) {
	return parseInt(a.id()) - parseInt(b.id());
}

/**
 * Check for a Google Book preview after the main page loads
 */
function rdetailCheckForGBPreview() {
	if (!rdetailGoogleBookPreview) return;
        dojo.addOnLoad(function() {
		searchForGBPreview( cleanISBN(record.isbn()) );
	});
}

/**
 *
 * @param {DOM object} isbn The form element containing the input parameters "isbns"
 */
function searchForGBPreview( isbn ) {
	dojo.require("dojo.io.script");
	dojo.io.script.get({"url": "https://www.google.com/jsapi"});
	dojo.io.script.get({"url": "https://www.googleapis.com/books/v1/volumes", "content": { "q": "isbn:" + isbn, "callback": "GBPreviewCallback"}});
}

/**
 * This function is the call-back function for the JSON scripts which 
 * executes a Google book search response.
 *
 * XXX I18N of text needed
 *
 * @param {JSON} GBPBookInfo is the JSON object pulled from the Google books service.
 */
function GBPreviewCallback(GBPBookInfo) {
	if (GBPBookInfo.totalItems < 1) return;

	var accessInfo = GBPBookInfo.items[0].accessInfo;
	if ( !accessInfo ) {
		return;
	}

	if ( accessInfo.embeddable ) {
		// Add a button below the book cover image to load the preview.
		GBPBadge = document.createElement( 'img' );
		GBPBadge.src = 'https://www.google.com/intl/en/googlebooks/images/gbs_preview_button1.gif';
		GBPBadge.title = $('rdetail_preview_badge').innerHTML;
		GBPBadge.style.border = 0;
		GBPBadgelink = document.createElement( 'a' );
		GBPBadgelink.href = 'javascript:rdetailShowExtra("preview");';
		GBPBadgelink.appendChild( GBPBadge );
		$('rdetail_image_cell').appendChild( GBPBadgelink );
		$('rdetail_preview_div').style.height = 600;

		/* Display the "Preview" tab in the Extras section */
		unHideMe( $('rdetail_preview_link' ) );
	}
}

/**
 *  This is called when the user clicks on the 'Preview' link.  We assume
 *  a preview is available from Google if this link was made visible.
 *
 * XXX I18N of Google Book Preview language attribute needed
 */
function rdetailDisplayGBPreview() {
	unHideMe($('rdetail_extras_loading'));
	GBPreviewPane = $('rdetail_preview_div');
	if ( GBPreviewPane.getAttribute('loaded') == null ||
		GBPreviewPane.getAttribute('loaded') == "false" ) {
		google.load("books", "0", {"callback" : rdetailGBPViewerLoadCallback, "language": "en"} );
		GBPreviewPane.setAttribute('loaded', 'true');
	}
}

function rdetailGBPViewerLoadCallback() {
	hideMe($('rdetail_extras_loading'));
	var GBPViewer = new google.books.DefaultViewer(document.getElementById('rdetail_preview_div'));
	GBPViewer.load('ISBN:' + cleanISBN(record.isbn()) );

}

function rdetailDrawExpandedHoldings(anchor, bibid, type) {
    var offsets = {"basic": 0, "index": 0, "supplement": 0};
    var limit = 10; /* XXX give user control over this? */
    var target_id = "holding_type_" + type;
    var target = dojo.byId(target_id);

    anchor.innerHTML = "[-]";
    anchor.oldonclick = anchor.onclick;
    anchor.onclick = function() {
        anchor.onclick = anchor.oldonclick;
        anchor.innerHTML = "[+]";
        dojo.empty(target);
    };

    function _load() {
        dojo.empty(target);
        fieldmapper.standardRequest(
            ["open-ils.serial",
                "open-ils.serial.received_siss.retrieve.by_bib.atomic"], {
                "params": [bibid, {"offset": offsets[type], "limit": limit}],
                "async": true,
                "oncomplete": function(r) {
                    try {
                        if (msg = r.recv().content()) { /* sic, assignment */
                            if (!msg.length) return;
                            offsets[type] += msg.length;
                            var table = dojo.create("table", null, target);
                            dojo.forEach(
                                msg, function(o) {
                                    var tr = dojo.create("tr", null, table);
                                    dojo.create(
                                        "td", {
                                            "innerHTML": o.issuance.label(),
                                            "style": {"paddingLeft": "3em"}
                                        }, tr
                                    );

                                    if (!o.has_units) return;
                                    /* can't place holds if no units */
                                    var td = dojo.create("td", null, tr);
                                    dojo.create(
                                        "a", {
                                            "href":"javascript:void(0);",
                                            "style": {"marginLeft": "1.5em"},
                                            "onclick": function() {
                                                holdsDrawEditor({
                                                    "type": "I",
                                                    "issuance": o.issuance.id()
                                                });
                                            },
                                            "innerHTML": "[" +
                                                opac_strings.PLACE_HOLD + "]"
                                        }, td
                                    );
                                }
                            );
                            if (msg.length == limit) {
                                dojo.create("br", null, target);
                                dojo.create(
                                    "a", {
                                        "href": "javascript:void(0);",
                                        "innerHTML":
                                            "[" + opac_strings.MORE + "]",
                                        "onclick": _load
                                    }, target
                                );
                            }
                        }
                    } catch (E) {
                        void(0);
                    }
                }
            }
        );
    }
    _load();
}
