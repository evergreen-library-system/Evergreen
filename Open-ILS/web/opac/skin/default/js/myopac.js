
attachEvt("common", "run", myOPACInit );
//attachEvt("common", "loggedIn", myOPACInit );
attachEvt('common','locationUpdated', myopacReload );

var fleshedUser = null;
var fleshedContainers = {};
var holdCache = {};
var holdStatusCache = {};


function clearNodes( node, keepArray ) {
	if(!node) return;
	for( var n in keepArray ) node.removeChild(keepArray[n]);
	removeChildren(node);
	for( var n in keepArray ) node.appendChild(keepArray[n]);
}

function myOPACInit() {
	if(!(G.user && G.user.session)) initLogin();
	else myOPACChangePage( "summary" );

    $('myopac_holds_thaw_date_input').onkeyup = 
        function(){holdsVerifyThawDateUI('myopac_holds_thaw_date_input'); }
    $('myopac_holds_thaw_date_input').onchange = 
        function(){holdsVerifyThawDateUI('myopac_holds_thaw_date_input'); }
}

function myopacReload() {
	//swapCanvas($('myopac_reloading'));
	var a = {};
	a[PARAM_LOCATION] = getNewSearchLocation();
	a[PARAM_DEPTH] = getNewSearchDepth();
	hideMe($('canvas_main'));
	goTo(buildOPACLink(a, true));
}


function myOPACChangePage( page ) {
	showCanvas();

	var s = $("myopac_summary_td");
	var c = $("myopac_checked_td");
	var f = $("myopac_fines_td");
	var h = $("myopac_holds_td");
	var p = $("myopac_prefs_td");
	var b = $('myopac_bookbag_td');

	var ss = $("myopac_summary_div");
	var cc = $("myopac_checked_div");
	var ff = $("myopac_fines_div");
	var hh = $("myopac_holds_div");
	var pp = $("myopac_prefs_div");
	var bb = $('myopac_bookbag_div');

	var cls = "myopac_link";
	var acls = "myopac_link_active";

	hideMe(ss);
	hideMe(cc); hideMe(ff);
	hideMe(hh); hideMe(pp);
	hideMe(bb);

	removeCSSClass(s, acls );
	removeCSSClass(c, acls );
	removeCSSClass(f, acls );
	removeCSSClass(h, acls );
	removeCSSClass(p, acls );
	removeCSSClass(b, acls );

	switch( page ) {

		case "summary": 
			unHideMe(ss);
			addCSSClass(s, acls );
			myOPACShowSummary();
			break;

		case "checked": 
			unHideMe(cc);
			addCSSClass(c, acls );
			myOPACShowChecked();
			break;

		case "holds": 
			unHideMe(hh);
			addCSSClass(h, acls );
			myOPACShowHolds();
			break;

		case "fines": 
			unHideMe(ff);
			addCSSClass(f, acls );
			myOPACShowFines();
			break;

		case "prefs": 
			unHideMe(pp);
			addCSSClass(p, acls );
			myOPACShowPrefs();
			break;

		case 'bookbag':
			unHideMe(bb);
			addCSSClass(b, acls);
			myOPACShowBookbags();
			break;
	}
}

function myOPACShowChecked() {
	if(checkedDrawn) return;
	var req = new Request(FETCH_CHECKED_OUT_SUM, G.user.session, G.user.id());	
	req.callback(myOPACDrawCheckedOutSlim);
	req.send();

	var nreq = new Request(FETCH_NON_CAT_CIRCS, G.user.session);
	nreq.callback(myOPACDrawNonCatCircs);
	nreq.send();
}


var checkedRowTemplate;
var circsCache = new Array();
var checkedDrawn = false;

function moClearCheckedTable() {
	var tbody			= $("myopac_checked_tbody");
	var loading			= $("myopac_checked_loading");
	var none				= $("myopac_checked_none");
	clearNodes( tbody, [ loading, none ] );
}

var __can_renew_one = false;

function myOPACDrawCheckedOutSlim(r) {

	var checked			= r.getResultObject();
	var tbody			= $("myopac_checked_tbody");
	var loading			= $("myopac_checked_loading");
	var none				= $("myopac_checked_none");

   __can_renew_one = false;

	if(checkedDrawn) return;
	checkedDrawn = true;
	if(!checkedRowTemplate) 
		checkedRowTemplate = tbody.removeChild($("myopac_checked_row"));

   moClearCheckedTable();

	hideMe(loading); /* remove all children and start over */
	if(!(checked && (checked.out || checked.overdue))) {
		unHideMe(none);
		return;
	}

	for( var i = 0; i < checked.overdue.length; i++ ) {
		var req = new Request(FETCH_CIRC_BY_ID, G.user.session, checked.overdue[i]);
		req.request.tbody = tbody;
		req.request.od = true;
		req.callback(myOPACDrawCheckedItem);
		req.send();
	}


	for( var i = 0; i < checked.out.length; i++ ) {
		var req = new Request(FETCH_CIRC_BY_ID, G.user.session, checked.out[i]);
		req.request.tbody = tbody;
		req.callback(myOPACDrawCheckedItem);
		req.send();
	}

   appendClear($('mo_items_out_count'), 
      text(new String( parseInt(checked.overdue.length) + parseInt(checked.out.length) )) );

   if( checked.overdue.length > 0 ) {
      addCSSClass($('mo_items_overdue_count'), 'overdue');
      appendClear($('mo_items_overdue_count'),
         text(new String( parseInt(checked.overdue.length) )) );
   }

}


function myOPACDrawCheckedItem(r) {

	var circ = r.getResultObject();
	var tbody = r.tbody;
	var row = checkedRowTemplate.cloneNode(true);
	row.id = 'myopac_checked_row_ ' + circ.id();
   row.setAttribute('circid', circ.id());

	var due = _trimTime(circ.due_date());

	var dlink = $n( row, "myopac_checked_due" );
	var rlink = $n( row, "myopac_checked_renewals" );
	//var rnlink = $n( row, "myopac_checked_renew_link" );

	//if( r.od ) due = elem('b', {style:'color:red;font-size:110%'},due);
	if( r.od ) {
      due = elem('b', null, due);
      addCSSClass(due, 'overdue');
   } else {
      due = text(due);
   }

	dlink.appendChild(due);
	rlink.appendChild(text(circ.renewal_remaining()));
	unHideMe(row);
	//rnlink.setAttribute('href', 'javascript:myOPACRenewCirc("'+circ.id()+'");');
	circsCache.push(circ);

	if( circ.renewal_remaining() < 1 ) {
      $n(row, 'selectme').disabled = true;
      if(!__can_renew_one)
         $('mo_renew_button').disabled = true;
   } else {
      __can_renew_one = true;
      $('mo_renew_button').disabled = false;
      $n(row, 'selectme').disabled = false;
   }

	tbody.appendChild(row);

	var req = new Request(FETCH_MODS_FROM_COPY, circ.target_copy() );
	req.request.alertEvent = false;
	req.request.circ = circ.id();
	req.request.copy = circ.target_copy();
	req.callback(myOPACDrawCheckedTitle);
	req.send();
}

var __circ_titles = {};

function myOPACDrawCheckedTitle(r) {
	var record = r.getResultObject();
	var circid = r.circ;

	if(!record || checkILSEvent(record)) {
		var req = new Request( FETCH_COPY, r.copy );
		req.request.circ = circid
		req.callback(myOPACDrawNonCatalogedItem);
		req.send();
		return;
	}

	var row = $('myopac_checked_row_ ' + circid);
	var tlink = $n( row, "myopac_checked_title_link" );
	var alink = $n( row, "myopac_checked_author_link" );
	buildTitleDetailLink(record, tlink);
	buildSearchLink(STYPE_AUTHOR, record.author(), alink);
   __circ_titles[circid] = record.title();
}

function myOPACDrawNonCatalogedItem(r) {
	var copy = r.getResultObject();
	var circid = r.circ;

	var row = $('myopac_checked_row_ ' + circid);
	var tlink = $n( row, "myopac_checked_title_link" );
	var alink = $n( row, "myopac_checked_author_link" );

	tlink.parentNode.appendChild(text(copy.dummy_title()));
	alink.parentNode.appendChild(text(copy.dummy_author()));
   __circ_titles[circid] = copy.dummy_title();
}


/*
function myOPACRenewCirc(circid) {

	var circ;
	for( var i = 0; i != circsCache.length; i++ ) 
		if(circsCache[i].id() == circid)
			circ = circsCache[i];

	if(!confirm($('myopac_renew_confirm').innerHTML)) return;

	var req = new Request(RENEW_CIRC, G.user.session, 
		{ patron : G.user.id(), copyid : circ.target_copy(), opac_renewal : 1 } );
	req.request.alertEvent = false;
	req.send(true);
	var res = req.result();

	if(checkILSEvent(res) || checkILSEvent(res[0])) {
		alertId('myopac_renew_fail');
		return;
	}

	alert($('myopac_renew_success').innerHTML);	
	checkedDrawn = false;
	myOPACShowChecked();
}
*/



function myOPACShowHolds() {
	var req = new Request(FETCH_HOLDS, G.user.session, G.user.id());	
	req.callback(myOPACDrawHolds);
	req.send();
    $('myopac_holds_actions_none').selected = true;
}

var holdsTemplateRowOrig;
var holdsTemplateRow;
var myopacForceHoldsRedraw = false;
function myOPACDrawHolds(r) {

	var tbody = $("myopac_holds_tbody");
	if(holdsTemplateRow && !myopacForceHoldsRedraw) return;
    myopacForceHoldsRedraw = false;

	if(holdsTemplateRowOrig) {
		holdsTemplateRow = holdsTemplateRowOrig;
		removeChildren(tbody);
	} else {
		holdsTemplateRow = tbody.removeChild($("myopac_holds_row"));
		holdsTemplateRowOrig = holdsTemplateRow;
	}

	hideMe($('myopac_holds_loading'));

	var holds = r.getResultObject();

	if(!holds || holds.length < 1) unHideMe($('myopac_holds_none'));
	for( var i = 0; i != holds.length; i++ ) {

		var h = holds[i];
		holdCache[h.id()] = h;

		var row = holdsTemplateRow.cloneNode(true);
		row.id = "myopac_holds_row_" + h.id();

		var form = $n(row, "myopac_holds_formats");
		form.id = "myopac_holds_form_" + h.id();

		var orglink = $n(row, "myopac_holds_location");
		orglink.appendChild(text(findOrgUnit(h.pickup_lib()).name()));

		tbody.appendChild(row);

		$n(row,'myopac_holds_edit_link').setAttribute(
			'href','javascript:myOPACEditHold("'+ h.id()+'");'); 

        if(isTrue(h.frozen())) {
            hideMe($n(row, 'myopac_hold_unfrozen_true'))
            unHideMe($n(row, 'myopac_hold_unfrozen_false'))
            if(h.thaw_date()) {
                var d = dojo.date.stamp.fromISOString(h.thaw_date());
                $n(row, 'myopac_holds_frozen_until').appendChild(text(dojo.date.locale.format(d, {selector: 'date', fullYear: true})));
            }
        } else {
            unHideMe($n(row, 'myopac_hold_unfrozen_true'))
            hideMe($n(row, 'myopac_hold_unfrozen_false'))
        }

        $n(row, 'myopac_holds_selected_chkbx').checked = false;

        if(h.expire_time()) {
            var exp_date = dojo.date.stamp.fromISOString(h.expire_time());
            $n(row, 'myopac_hold_expire_time').appendChild(
                text(dojo.date.locale.format(exp_date, {selector:'date'})));
        }

		unHideMe(row);

        var interval = fetchOrgSettingDefault(G.user.home_ou(), 'circ.hold_expire_alert_interval');
        if(interval) {
            secs = interval_to_seconds(interval) * 1000;
            var diff = exp_date.getTime() - new Date().getTime();
            if(diff < secs)
                addCSSClass($n(row, 'myopac_hold_expire_time'), 'hold_expire_warning');
        }

        myOPACDrawHoldTitle(h);
        myOPACDrawHoldStatus(h);
    }
}

function myOPACEditHold(holdid) {
	var hold = holdCache[holdid];

	holdsDrawEditor( 
		{ 
			editHold : hold,
			onComplete : function(){ 
				holdsTemplateRow = null;
				myOPACShowHolds(); 
			}
		}
	);
}


function myOPACDrawHoldStatus(hold) {
	var req = new Request(FETCH_HOLD_STATUS, G.user.session, hold.id() );
	req.callback(myOShowHoldStatus);
	req.request.hold = hold;
	req.send();
}

var myopacShowHoldEstimate = false;
function myOShowHoldStatus(r) {

	var hold = r.hold;
	var qstats = r.getResultObject();
    holdStatusCache[hold.id()] = qstats;

	var row = $("myopac_holds_row_" + r.hold.id());

    if(qstats.estimated_wait || myopacShowHoldEstimate) {
        myopacShowHoldEstimate = true;
        if(qstats.estimated_wait)
            $n(row, 'myopac_holds_estimated_wait').appendChild(text(qstats.estimated_wait));
        unHideMe($('myopac_holds_estimated_wait_column'));
        unHideMe($n(row, 'myopac_holds_estimated_wait'));
    } 

	if( qstats.status == 4 ) {
		unHideMe($n(row, 'hold_status_available'));
		hideMe($n(row, 'myopac_holds_cancel_link'));
	}

    if(false) {
        var node = $n(row, 'hold_qstats');
        // XXX best way to display this info + dojo i18n
        node.appendChild(text('hold #' + qstats.queue_position+' of '+qstats.queue_position+' and '+qstats.potential_copies+' item(s)'));
        unHideMe(node);

    } else {
	    if( qstats.status < 3 )
		    unHideMe($n(row, 'hold_status_waiting'));
    
	    if( qstats.status == 3 )
		    unHideMe($n(row, 'hold_status_transit'));
    }
}


function myOPACDrawHoldTitle(hold) {
	var method;

	if( hold.hold_type() == 'T' || hold.hold_type() == 'M' ) {
		if(hold.hold_type() == "M") method = FETCH_MRMODS;
		if(hold.hold_type() == "T") method = FETCH_RMODS;
		var req = new Request(method, hold.target());
		req.callback(myOPACFleshHoldTitle);
		req.request.hold = hold;
		req.request.alertEvent = false;
		req.send();

	} else {
		holdFetchObjects(hold, 
			function(a) { _myOPACFleshHoldTitle(hold, a);});
	}
}

function myOPACFleshHoldTitle(r) {
	var rec = r.getResultObject();
	_myOPACFleshHoldTitle(r.hold, {recordObject: rec});
}

function _myOPACFleshHoldTitle(hold, holdObjects) {

	var record = holdObjects.recordObject;
	var volume	= holdObjects.volumeObject;
	var copy	= holdObjects.copyObject;

	var row = $("myopac_holds_row_" + hold.id());
	var title_link = $n(row, "myopac_holds_title_link");
	var author_link = $n(row, "myopac_holds_author_link");

	if(!record || checkILSEvent(record) ) {
		addCSSClass(row, 'invalid_hold');
		$n(row, 'myopac_holds_edit_link').setAttribute('href', 'javascript:void(0);');
		$n(row, 'myopac_holds_edit_link').onclick = function(){alertId('invalid_hold');};
		return;
	}

	buildTitleDetailLink(record, title_link);
	buildSearchLink(STYPE_AUTHOR, record.author(), author_link);

	if( volume ) {
		$n(row, 'volume').appendChild(text(volume.label()));
		unHideMe($n(row, 'vol_copy'));
		if(copy) $n(row, 'copy').appendChild(text(copy.barcode()));
	}

	var form = $("myopac_holds_form_" + hold.id());

	if(form) {
		var mods_formats = record.types_of_resource();

		if( hold.hold_type() == 'M' ) {
			var data = holdsParseMRFormats(hold.holdable_formats());
			mods_formats = data.mods_formats;
		}

		for( var i = 0; i < mods_formats.length; i++ ) {
			var img = elem("img");
			setResourcePic(img, mods_formats[i]);
			form.appendChild(img);
		}
	}
}

var finesShown = false;
function myOPACShowFines() {
	if(finesShown) return; finesShown = true;
	var req = new Request(FETCH_FINES_SUMMARY, G.user.session, G.user.id() );
	req.callback(_myOPACShowFines);
	req.send();
}

function _myOPACShowFines(r) {
	hideMe($('myopac_fines_summary_loading'));
	unHideMe($('myopac_fines_summary_row'));

	var summary = r.getResultObject();
	var total	= "0.00"; /* localization? */
	var paid		= "0.00";
	var balance = "0.00";
	if( instanceOf(summary,mous) ) {

		total		= _finesFormatNumber(summary.total_owed());
		paid		= _finesFormatNumber(summary.total_paid());
		balance	= _finesFormatNumber(summary.balance_owed());

		var req = new Request(FETCH_TRANSACTIONS, G.user.session, G.user.id() );
		req.callback(myOPACShowTransactions);
		req.send();
	}

	$('myopac_fines_summary_total').appendChild(text(total));
	$('myopac_fines_summary_paid').appendChild(text(paid));
	$('myopac_fines_summary_balance').appendChild(text(balance));
}

function _finesFormatNumber(num) {
	if(isNull(num)) num = 0;
	num = num + "";
	if(num.length < 2 || !num.match(/\./)) num += ".00";
	if(num.match(/\./) && num.charAt(num.length-2) == '.') num += "0";
	return num;
}          

//function _trimTime(time) { if(!time) return ""; return time.replace(/\ .*/,""); }
function _trimTime(time) { 
	if(!time) return ""; 
    var d = dojo.date.stamp.fromISOString(time);
    if(!d) return ""; /* date parse failed */
    return d.iso8601Format('YMD');
}

function _trimSeconds(time) { 
    if(!time) return ""; 
    var d = dojo.date.stamp.fromISOString(time);
    if(!d) return ""; /* date parse failed */
    return d.iso8601Format('YMDHM',null,true,true);
}

function myOPACShowTransactions(r) {

	if(myopacGenericTransTemplate || myopacCircTransTemplate) return;

	var transactions = r.getResultObject();

	for( var idx in transactions ) {

		var trans	= transactions[idx].transaction;
		var record	= transactions[idx].record;
		var circ		= transactions[idx].circ;

		if(trans.xact_type() == 'circulation') 
			myOPACShowCircTransaction(trans, record, circ);

		else if(trans.xact_type() == 'grocery' ) 
			myopacShowGenericTransaction( trans );
	}
}

var myopacGenericTransTemplate;
function myopacShowGenericTransaction( trans ) {
	var tbody = $('myopac_trans_tbody');

	if(!myopacGenericTransTemplate) {
		myopacGenericTransTemplate = 
			tbody.removeChild($('myopac_trans_row'));
		removeChildren(tbody);
	}

	var row = myopacGenericTransTemplate.cloneNode(true);

	$n(row,'myopac_trans_start').appendChild(
			text(_trimSeconds(trans.xact_start())));

	$n(row,'myopac_trans_last_payment').appendChild(
			text(_trimSeconds(trans.last_payment_ts())));

	$n(row,'myopac_trans_init_amount').appendChild(
			text(_finesFormatNumber(trans.total_owed())));

	$n(row,'myopac_trans_total_paid').appendChild(
			text(_finesFormatNumber(trans.total_paid())));

	$n(row,'myopac_trans_balance').appendChild(
			text(_finesFormatNumber(trans.balance_owed())));

	var req = new Request(FETCH_MONEY_BILLING, G.user.session, trans.id());
	req.send(true);
	var bills = req.result();
	if(bills && bills[0])
		$n(row,'myopac_trans_bill_type').appendChild(
				text(bills[0].billing_type()));

	tbody.appendChild(row);
	unHideMe($('myopac_trans_div'));
}



/* draws a circulation transaction summary */
var myopacCircTransTemplate;
function myOPACShowCircTransaction(trans, record, circ) {
	var tbody = $('myopac_circ_trans_tbody');

	if(!myopacCircTransTemplate) {
		myopacCircTransTemplate = tbody.removeChild($('myopac_circ_trans_row'));
		removeChildren(tbody);
	}

	var row = myopacCircTransTemplate.cloneNode(true);

	if(record) {
		buildTitleDetailLink(record, $n(row,'myopac_circ_trans_title'));

		$n(row,'myopac_circ_trans_author').appendChild(text(
			normalize(truncate(record.author(), 65))));

	} else {

		var req = new Request( FETCH_COPY, circ.target_copy() );
		req.alertEvents = false;
		req.send(true);
		var copy = req.result();
		if( copy ) {
			$n(row,'myopac_circ_trans_title').appendChild(text(copy.dummy_title()));
			$n(row,'myopac_circ_trans_author').appendChild(text(copy.dummy_author()));
		}
	}


	$n(row,'myopac_circ_trans_start').
		appendChild(text(_trimTime(trans.xact_start())));

   var due = _trimTime(circ.due_date());
	var checkin = _trimTime(circ.stop_fines_time());

	$n(row,'myopac_circ_trans_due').appendChild(text(due))
	if(checkin)
		appendClear($n(row,'myopac_circ_trans_finished'), text(checkin));
	if(circ.stop_fines() == 'LOST')
		appendClear($n(row,'myopac_circ_trans_finished'), text(circ.stop_fines()));
	if(circ.stop_fines() == 'CLAIMSRETURNED')
		appendClear($n(row,'myopac_circ_trans_finished'), text(""));


	$n(row,'myopac_circ_trans_balance').
		appendChild(text(_finesFormatNumber(trans.balance_owed())));

	tbody.appendChild(row);
	unHideMe($('myopac_circ_trans_div'));
}


function myOPACSavePrefs() {
	G.user.prefs[PREF_HITS_PER] = getSelectorVal($('prefs_hits_per'));
	G.user.prefs[PREF_DEF_FONT] = getSelectorVal($('prefs_def_font'));
	G.user.prefs[PREF_HOLD_NOTIFY] = getSelectorVal($('prefs_hold_notify'));
	G.user.prefs[PREF_DEF_DEPTH] = getSelectorVal($('prefs_def_range'));

	if( $('myopac_pref_home_lib').checked == true )
		G.user.prefs[PREF_DEF_LOCATION] = null;
	else
		G.user.prefs[PREF_DEF_LOCATION] = getSelectorVal($('prefs_def_location'));

	if(commitUserPrefs())
		alert($('prefs_update_success').innerHTML);
	else alert($('prefs_update_failure').innerHTML);
}


function myOPACShowDefFont() {
	var font;
	if(G.user.prefs[PREF_DEF_FONT])
		font = G.user.prefs[PREF_DEF_FONT];
	else font = "regular";
	setSelector($('prefs_def_font'), font);
}

function myOPACShowHoldNotify() {
	var pref = G.user.prefs[PREF_HOLD_NOTIFY];

	if(pref) {
		if(pref.match(/email/i) && pref.match(/phone/i)) {
			setSelector($('prefs_hold_notify'), 'phone:email');
		} else if( pref.match(/email/i) ) {
			setSelector($('prefs_hold_notify'), 'email');
		} else if( pref.match(/phone/i) ) {
			setSelector($('prefs_hold_notify'), 'phone');
		}

	} else {
		setSelector($('prefs_hold_notify'), 'phone:email');
	}
}

function myOPACShowPrefs() {
	grabUserPrefs();
	myOPACShowHitsPer();
	myOPACShowDefFont();
	myOPACShowHoldNotify();
	myOPACShowDefLocation();
	hideMe($('myopac_prefs_loading'));
}

var defSearchLocationDrawn = false;
var defDepthIndex = 0;
function myOPACShowDefLocation() {

	var selector = $('prefs_def_location');
	var rsel = $('prefs_def_range');

	if(!defSearchLocationDrawn) {

		defSearchLocationDrawn = true;

		var org = G.user.prefs[PREF_DEF_LOCATION];

		if(!org) {
			$('myopac_pref_home_lib').checked = true;
			$('prefs_def_location').disabled = true;
			org = G.user.home_ou();
		}

		buildOrgSel(selector, globalOrgTree, 0);

		globalOrgTypes = globalOrgTypes.sort(
			function(a, b) {
				if( a.depth() < b.depth() ) return -1;
				return 1;
			}
		);

		iterate(globalOrgTypes,
			function(t) {
				if( t.depth() <= findOrgDepth(org) ) {
					setSelectorVal(rsel, defDepthIndex++, t.opac_label(), t.depth());
					if( t.depth() == findOrgDepth(org) ) 
						setSelector(rsel, t.depth());
				}
			}
		);
	}

	setSelector(selector, org);
}

function myOPACShowHitsPer() {
	var hits = 10;
	if(G.user.prefs[PREF_HITS_PER])
		hits = G.user.prefs[PREF_HITS_PER];
	var hitsSel = $('prefs_hits_per');
	setSelector(hitsSel, hits);
}

var userShown = false;
function myOPACShowSummary() {
	if(userShown) return; userShown = true;
	var req = new Request(FETCH_FLESHED_USER,G.user.session, G.user.id());
	req.callback(_myOPACSummaryShowUer);
	req.send();
}

var addrRowTemplate;
var notesTemplate;
function _myOPACSummaryShowUer(r) {

	var user = r.getResultObject();
	fleshedUser = user;
	if(!user) return;

    var expireDate = dojo.date.stamp.fromISOString(user.expire_date());
    if( expireDate < new Date() ) {
        appendClear($('myopac.expired.date'), expireDate.iso8601Format('YMD'));
        unHideMe($('myopac.expired.alert'));
    }

	var iv1 = user.ident_value()+'';
	if (iv1.length > 4) iv1 = iv1.replace(new RegExp(iv1.substring(0,iv1.length - 4)), '***********');

	appendClear($('myopac_summary_prefix'),text(user.first_given_name()));
	appendClear($('myopac_summary_first'),text(user.first_given_name()));
	appendClear($('myopac_summary_middle'),text(user.second_given_name()));
	appendClear($('myopac_summary_dayphone'),text(user.day_phone()));
	appendClear($('myopac_summary_eveningphone'),text(user.evening_phone()));
	appendClear($('myopac_summary_otherphone'),text(user.other_phone()));
	appendClear($('myopac_summary_last'),text(user.family_name()));
	appendClear($('myopac_summary_suffix'),text(user.suffix()));
	appendClear($('myopac_summary_username'),text(user.usrname()));
	appendClear($('myopac_summary_email'),text(user.email()));
	appendClear($('myopac_summary_barcode'),text(user.card().barcode()));
	appendClear($('myopac_summary_ident1'),text(iv1));
	appendClear($('myopac_summary_homelib'),text(findOrgUnit(user.home_ou()).name()));
	appendClear($('myopac_summary_create_date'),text(_trimTime(user.create_date())));

	var req = new Request( 
		FETCH_USER_NOTES, G.user.session, {pub:1, patronid:G.user.id()});
	req.callback(myopacDrawNotes);
	req.send();


	var tbody = $('myopac_addr_tbody');
	var template;

	if(addrRowTemplate) { 
		template = addrRowTemplate;
	} else {
		template = tbody.removeChild($('myopac_addr_row'));
		addrRowTemplate = template;
	}
	removeChildren(tbody);

    var addrs = user.addresses();
	for( var a in addrs ) {
        var addr = addrs[a];
        if(addr.replaces() != null) continue;
		var row = template.cloneNode(true);
		myOPACDrawAddr(row, addr, addrs);
		tbody.appendChild(row);
	}
}


function myopacDrawNotes(r) {
	var notes = r.getResultObject();
	var tbody = $('myopac.notes.tbody');
	if(!notesTemplate)
		notesTemplate = tbody.removeChild($('myopac.notes.tr'));
	removeChildren(tbody);

	iterate(notes, 
		function(note) {
			unHideMe($('myopac.notes.div'));
			var row = notesTemplate.cloneNode(true);
			$n(row, 'title').appendChild(text(note.title()));
			$n(row, 'value').appendChild(text(note.value()));
			tbody.appendChild(row);
		}
	);
}



function myOPACDrawAddr(row, addr, addrs) {
    appendClear($n(row, 'myopac_addr_type'),text(addr.address_type()));
    var street = (addr.street2()) ? addr.street1() + ", " + addr.street2() : addr.street1();
    appendClear($n(row, 'myopac_addr_street'),text(street));
    appendClear($n(row, 'myopac_addr_city'),text(addr.city()));
    appendClear($n(row, 'myopac_addr_county'),text(addr.county()));
    appendClear($n(row, 'myopac_addr_state'),text(addr.state()));
    appendClear($n(row, 'myopac_addr_zip'),text(addr.post_code()));

    /* if we have a replacement address, plop it into the table next to this addr */
    var repl = grep(addrs,
        function(a) { 
            return a.replaces() == addr.id(); 
        } 
    );

    if(repl) {
        repl = repl[0];
        unHideMe($n(row, 'myopac_pending_addr_td'));
        $n(row, 'myopac_pending_addr_type').value = repl.address_type();
        var street = (repl.street2()) ? repl.street1() + ", " + repl.street2() : repl.street1();
        $n(row, 'myopac_pending_addr_street').value = street;
        $n(row, 'myopac_pending_addr_city').value = repl.city();
        $n(row, 'myopac_pending_addr_county').value = repl.county();
        $n(row, 'myopac_pending_addr_state').value = repl.state();
        $n(row, 'myopac_pending_addr_zip').value = repl.post_code();
    }
}


function myOPACUpdateUsername() {
	var username = $('myopac_new_username').value;
	if(username == null || username == "") {
		alert($('myopac_username_error').innerHTML);
		return;
	}

	if( username.match(/.*\s.*/) ) {
		alert($('myopac_invalid_username').innerHTML);
		return;
	}

    r = fetchOrgSettingDefault(globalOrgTree.id(), 'opac.barcode_regex');
    if(r) REGEX_BARCODE = new RegExp(r);

    if(username.match(REGEX_BARCODE)) {
        alert($('myopac_invalid_username').innerHTML);
        return;
    }

	/* first see if the requested username is taken */
	var req = new Request(CHECK_USERNAME, G.user.session, username);
	req.send(true);
	var res = req.result();
	/* If the username does not already exist, res will be null;
	 * we can move on to updating the username.
	 * 
	 * If the username does exist, then res will be the user ID.
	 * G.user.id() gives us the currently authenticated user ID.
	 * If res == G.user.id(), we try to update the username anyways.
	 */
	if( res !== null && res != G.user.id() ) {
		alertId('myopac_username_dup');
		return;
	}

	var req = new Request(UPDATE_USERNAME, G.user.session, username );
	req.send(true);
	if(req.result()) {

		var evt;
		var res = req.result();
		if(evt = checkILSEvent(res)) {
			alertILSEvent(res);
			return;
		}

		G.user.usrname(username);
		hideMe($('myopac_update_username_row'));
		userShown = false;
		alertId('myopac_username_success');
		myOPACShowSummary();
		return;
	}

	alert($('myopac_username_failure').innerHTML);
}

function myOPACUpdateEmail() {
	var email = $('myopac_new_email').value;
	if(email == null || email == "") {
		alert($('myopac_email_error').innerHTML);
		return;
	}

	var req = new Request(UPDATE_EMAIL, G.user.session, email );
	req.send(true);
	if(req.result()) {
		G.user.usrname(email);
		hideMe($('myopac_update_email_row'));
		userShown = false;
		alertId('myopac_email_success');
		myOPACShowSummary();
		return;
	}

	alert($('myopac_email_failure').innerHTML);
}


function myOPACUpdatePassword() {
	var curpassword = $('myopac_current_password').value;
	var password = $('myopac_new_password').value;
	var password2 = $('myopac_new_password2').value;

	if(	curpassword == null || curpassword == "" || 
			password == null || password == "" || 
			password2 == null || password2 == "" || password != password2 ) {
		alert($('myopac_password_error').innerHTML);
		return;
	}

	if(!strongPassword(password, true)) return;

	var req = new Request(UPDATE_PASSWORD, G.user.session, password, curpassword );
	req.send(true);
	if(req.result()) {
		hideMe($('myopac_update_password_row'));
		userShown = false;
		alertId('myopac_password_success');
		myOPACShowSummary();
		return;
	}

	alert($('myopac_password_failure').innerHTML);
}




var containerTemplate;
function myOPACShowBookbags(force) {

	var tbody =$('myopac_bookbag_tbody') ;

	if(!containerTemplate) 
		containerTemplate = tbody.removeChild($('myopac_bookbag_tr'));
	else if(!force) return;

	removeChildren(tbody);

	var containers = containerFetchAll();

	var found = false;
	for( var i in containers ) {
		found = true;
		var cont = containers[i];
		var row = containerTemplate.cloneNode(true);
		row.id = 'myopac_bookbag_row_' + cont.id();
		var link = $n(row, 'myopac_expand_bookbag');
		var dlink = $n(row, 'myopac_container_delete');
		link.appendChild( text(cont.name()) );
		link.setAttribute('href', 
			'javascript:myOPACExpandBookbag("' + cont.id() + '","' + cont.name() + '");');
		myOPACFetchBBItems( cont.id(), row );
		dlink.setAttribute('href', 'javascript:myOPACDeleteBookbag("'+cont.id()+'");');

		if( isTrue(cont.pub()) ) {
			unHideMe($n(row, 'myopac_bb_published_yes'));
			var link = $n(row, 'myopac_bb_published_view');
			link.setAttribute('href', buildExtrasLink( 'feed/bookbag/html-full/'+cont.id(), false));  
			link.setAttribute('target', '_blank' );
			unHideMe(link);

			link = $n(row, 'myopac_bb_published_atom');
			link.setAttribute('href', buildExtrasLink( 'feed/bookbag/rss2-full/'+cont.id(), false));  
			link.setAttribute('target', '_blank' );
			unHideMe(link);

			link = $n(row, 'myopac_bb_make_unpublished');
			link.setAttribute('href', 'javascript:myOPACMakeBBPublished("'+cont.id()+'", true);');
			unHideMe(link);

		} else { 
			unHideMe($n(row, 'myopac_bb_published_no')); 
			var link = $n(row, 'myopac_bb_make_published');
			link.setAttribute('href', 'javascript:myOPACMakeBBPublished("'+cont.id()+'");');
			unHideMe(link);
		}

		tbody.appendChild(row);	
	}

	if(!found) unHideMe($('myopac_bookbags_none'));
	else unHideMe($('myopac_bookbag_table'));	
}

function myOPACMakeBBPublished(bbid, hideme) {

	var bb = fleshedContainers[bbid];

	if(hideme) {
		if(!confirm($('myopac_make_unpublished_confirm').innerHTML)) return;
		bb.pub('f');
	} else {
		if(!confirm($('myopac_make_published_confirm').innerHTML)) return;
		bb.pub('t');
	}

	var result = containerUpdate(bb);

	var code = checkILSEvent(result);
	if(code) { alertILSEvent(result); return; }

	alert($('myopac_bb_update_success').innerHTML);
	myOPACShowBookbags(true);
}



function myOPACDeleteBookbag(id) {
	if( confirm( $('myopac_delete_bookbag_warn').innerHTML ) ) {
		var result = containerDelete(id);
		var code = checkILSEvent(result);
		if(code) { alertILSEvent(result); return; }
		alert($('myopac_bb_update_success').innerHTML);
		hideMe($('myopac_bookbag_items_table'));
		hideMe($('myopac_bookbag_items_name'));
		hideMe($('myopac_bookbag_no_items'));
		myOPACShowBookbags(true);
	}
}

function myOPACFetchBBItems( id, row, block ) {
	if(!block) {
		containerFlesh( id, _myOPACSetBBItems, { row: row }  );
	} else {
		var cont = containerFlesh(id);
		myOPACSetBBItems( cont, row );
	}
}

function _myOPACSetBBItems(r) { myOPACSetBBItems( r.getResultObject(), r.args.row ); }

function myOPACSetBBItems( container, row ) {
	fleshedContainers[container.id()] = container;
	var node = $n(row, 'myopac_bookbag_item_count');
	removeChildren(node);
	node.appendChild( text(container.items().length) );
}

var BBItemsRow;
function myOPACExpandBookbag( id, name ) {
	
	var tbody = $('myopac_bookbag_items_tbody');
	if(!BBItemsRow) BBItemsRow = tbody.removeChild($('myopac_bookbag_items_row'));
	removeChildren(tbody);
	removeChildren($('myopac_bookbag_items_name'));

	$('myopac_bookbag_items_name').appendChild(text(name));

	if( fleshedContainers[id] ) {
		var len = fleshedContainers[id].items().length;

		if( len == 0 ) {
			unHideMe($('myopac_bookbag_no_items'));
			hideMe($('myopac_bookbag_items_table'));
			return;
		}

		hideMe($('myopac_bookbag_no_items'));
		unHideMe($('myopac_bookbag_items_table'));

		for( var i = 0; i != len; i++ ) {
			var row = BBItemsRow.cloneNode(true);
			found = true;

			var item = fleshedContainers[id].items()[i];
			var tlink = $n(row,'myopac_bookbag_items_title');
			var alink = $n(row,'myopac_bookbag_items_author');

			var req = new Request( FETCH_RMODS, item.target_biblio_record_entry() );
			req.request.tlink = tlink;
			req.request.alink = alink;
			req.callback(myOPACShowBBItem);
			req.send();

			var clink = $n(row, 'myopac_bookbag_items_remove');
			clink.setAttribute('href', 'javascript:myOPACRemoveBBItem("'+item.id()+'","'+id+'","'+name+'");');

			tbody.appendChild(row);
		}
	}
}

function myOPACRemoveBBItem( id, containerid, container_name ) {
	if(!confirm($('myopac_remove_bb_item_confirm').innerHTML)) return;
	var stat = containerRemoveItem( id );
	if(stat) alert($('myopac_bb_update_success').innerHTML);
	myOPACFetchBBItems( containerid, $('myopac_bookbag_row_' + containerid), true);
	myOPACExpandBookbag( containerid, container_name );
}

function myOPACShowBBItem(r) {
	var record = r.getResultObject();
	buildTitleDetailLink(record, r.tlink);
	buildSearchLink(STYPE_AUTHOR, record.author(), r.alink);
}

function myOPACCreateBookbag() {
	var name = $('myopac_bookbag_new_name').value;	
	if(!name) return;

	var exists = false;
	for( var c in fleshedContainers ) { exists = true; break; }

	/* let them know what they are getting into... */
	if(!exists) if(!confirm($('bb_create_warning').innerHTML)) return;

	var result = containerCreate( name, $('bb_public_yes').checked );
	var code = checkILSEvent(result);
	if(code) { alertILSEvent(result); return; }
	if(result) alert($('myopac_bb_update_success').innerHTML);
	myOPACShowBookbags(true);
}


/* ---------------------------------------------------------------------- */
/* Non cat circs */
/* ---------------------------------------------------------------------- */

var nonCatCircIds;
var nonCatTypes;
/* if we have some circs, grab the non-cat types */
function myOPACDrawNonCatCircs(r) {
	var ids = r.getResultObject();
	if(ids.length == 0) return;
	nonCatCircIds = ids;
	unHideMe($('non_cat_circs_div'));
	var req = new Request(FETCH_NON_CAT_TYPES, G.user.home_ou());
	req.callback(myOPACDrawNonCatCircs2);
	req.send();
}


/* now we have circs and the types.. draw each one */
var nonCatTbody;
var nonCatRow;
function myOPACDrawNonCatCircs2(r) {
	nonCatTypes = r.getResultObject();
	nonCatTbody = $('non_cat_circs_tbody');
	if(!nonCatRow) nonCatRow = 
		nonCatTbody.removeChild($('non_cat_circs_row'));
	removeChildren(nonCatTbody);
	for( var i in nonCatCircIds ) {
		var req = new Request(FETCH_NON_CAT_CIRC, G.user.session, nonCatCircIds[i]);
		req.callback(myOPACDrawNonCatCirc);
		req.send();
	}
}


/* draw a single circ */
function myOPACDrawNonCatCirc(r) {
	var circ = r.getResultObject();


	var type = grep(nonCatTypes, 
		function(i){
			return (i.id() == circ.item_type());
		}
	)[0];


	var row = nonCatTbody.appendChild(nonCatRow.cloneNode(true));
	appendClear($n(row, 'circ_lib'), text(findOrgUnit(circ.circ_lib()).name()));
	appendClear($n(row, 'item_type'), text(type.name()));

	var duration = interval_to_seconds(type.circ_duration());
	duration = parseInt(duration + '000');

	var dtf = circ.circ_time();
    var start = dojo.date.stamp.fromISOString(circ.circ_time());
	var due = new Date(  start.getTime() + duration );
	appendClear($n(row, 'circ_time'), text(due.iso8601Format('YMDHM', null, true, true)));
}




function myopacSelectAllChecked() {
   __myopacSelectChecked(true);
}

function myopacSelectNoneChecked() {
   __myopacSelectChecked(false);
}

function __myopacSelectChecked(value) {
   var rows = myopacGetCheckedOutRows();
   for( var i = 0; i < rows.length; i++ ) {
      var row = rows[i];
      var box = $n(row, 'selectme');
      if( box && ! box.disabled )
      box.checked = value;
   }
}

function myopacGetCheckedOutRows() {
   var rows = [];
   var tbody = $('myopac_checked_tbody');
   var children = tbody.childNodes;
   for( var i = 0; i < children.length; i++ ) {
      var child = children[i];
      if( child.nodeName.match(/^tr$/i) ) 
         if( $n(child, 'selectme') ) 
            rows.push(child);
   }
   return rows;
}

var __renew_circs = [];

/* true if 1 renewal succeeded */
var __success_count = 0;

/* renews all selected circulations */
function myOPACRenewSelected() {
   var rows = myopacGetCheckedOutRows();
	if(!confirm($('myopac_renew_confirm').innerHTML)) return;
   __success_count = 0;

   for( var i = 0; i < rows.length; i++ ) {

      var row = rows[i];
      if( ! $n(row, 'selectme').checked ) continue;
      var circ_id = row.getAttribute('circid');

	   var circ;
	   for( var j = 0; j != circsCache.length; j++ ) 
		   if(circsCache[j].id() == circ_id)
			   circ = circsCache[j];

      __renew_circs.push(circ);
   }

    if( __renew_circs.length == 0 ) return;

    unHideMe($('my_renewing'));
    moClearCheckedTable();

    for( var i = 0; i < __renew_circs.length; i++ ) {
        var circ = __renew_circs[i];
        moRenewCirc( circ.target_copy(), G.user.id(), circ );
    }
}


/* renews a single circulation */
function moRenewCirc(copy_id, user_id, circ) {

   _debug('renewing circ ' + circ.id() + ' with copy ' + copy_id);
   var req = new Request(RENEW_CIRC, G.user.session, 
      {  patron : user_id, 
         copyid : copy_id, 
         opac_renewal : 1 
      } 
   );

   req.request.alertEvent = false;
   req.callback(myHandleRenewResponse);
   req.request.circ = circ;
   req.send();
}



/* handles the circ renew results */
function myHandleRenewResponse(r) {
   var res = r.getResultObject();
   var circ = r.circ;

   /* remove this circ from the list of circs to renew */
   __renew_circs = grep(__renew_circs, function(i) { return (i.id() != circ.id()); });

   _debug("handling renew result for " + circ.id());

   if(checkILSEvent(res) || checkILSEvent(res[0])) 
      alertIdText('myopac_renew_fail', __circ_titles[circ.id()]);
   else __success_count++;

   if(__renew_circs) return; /* more to come */

   __renew_circs = [];

	if( __success_count > 0 )
      alertIdText('myopac_renew_success', __success_count);

   hideMe($('my_renewing'));
   checkedDrawn = false;
    myOPACShowChecked();
}

/** ---- batch hold processing ------------ */


/* myopac_holds_checkbx */
function myopacSelectAllHolds() {
    var rows = getTableRows($("myopac_holds_tbody"));
    for(var i = 0; i < rows.length; i++) {
        cb = $n(rows[i], 'myopac_holds_selected_chkbx');
        if(cb) cb.checked = true;
    }
}

function myopacSelectNoneHolds() {
    var rows = getTableRows($("myopac_holds_tbody"));
    for(var i = 0; i < rows.length; i++) {
        cb = $n(rows[i], 'myopac_holds_selected_chkbx');
        if(cb) cb.checked = false;
    }
}

function myopacSelectedHoldsRows() {
    var r = [];
    var rows = getTableRows($("myopac_holds_tbody"));
    for(var i = 0; i < rows.length; i++) {
        cb = $n(rows[i], 'myopac_holds_selected_chkbx');
        if(cb && cb.checked)
            r.push(rows[i]);
    }
    return r;
}

var myopacProcessedHolds = 0;
var myopacHoldsToProcess = 0;
function myopacDoHoldAction() {

    var selectedRows = myopacSelectedHoldsRows();
    action = getSelectorVal($('myopac_holds_actions'));
    $('myopac_holds_actions_none').selected = true;
    if(selectedRows.length == 0) return;

    myopacProcessedHolds = 0;

    if(!confirmId('myopac.holds.'+action+'.confirm')) return;
    myopacSelectNoneHolds(); /* clear the selection */


    /* first, let's collect the holds that actually need processing and
        collect the full process count while we're at it */
    var holds = [];
    for(var i = 0; i < selectedRows.length; i++) {
        hold = holdCache[myopacHoldIDFromRow(selectedRows[i])];
        var qstats = holdStatusCache[hold.id()];
        switch(action) {
            case 'cancel':
                holds.push(hold);
                break;
            case 'thaw_date':
            case 'thaw':
                if(isTrue(hold.frozen()))
                    holds.push(hold);
                break;
            case 'freeze':
                if(!isTrue(hold.frozen()) && qstats.status < 3)
                    holds.push(hold);
                break;
        }
    }
    myopacHoldsToProcess = holds;
    if(myopacHoldsToProcess.length == 0) return;

    if(action == 'thaw_date' || action == 'freeze') 
        myopacDrawHoldThawDateForm();
    else
    myopacProcessHolds(action);
}


function myopacProcessHolds(action, thawDate) {

    myopacShowHoldProcessing();
    /* now we process them */
    for(var i = 0; i < myopacHoldsToProcess.length; i++) {

        hold = myopacHoldsToProcess[i];
        
        var req;
        switch(action) { 

            case 'cancel':
                req = new Request(CANCEL_HOLD, G.user.session, hold.id());
                break;
    
            case 'thaw':
                hold.frozen('f');
                hold.thaw_date(null);
                req = new Request(UPDATE_HOLD, G.user.session, hold);
                break;

            case 'thaw_date':
            case 'freeze':
                hold.frozen('t');
                hold.thaw_date(thawDate); 
                req = new Request(UPDATE_HOLD, G.user.session, hold);
                break;
                //thawDate = prompt($('myopac.holds.freeze.select_thaw').innerHTML);

        }

        req.callback(myopacBatchHoldCallback);
        req.send();
        req = null;
    }
}

function myopacDrawHoldThawDateForm() {
    hideMe($('myopac_holds_main_table'));
    unHideMe($('myopac_holds_thaw_date_form'));
    $('myopac_holds_thaw_date_input').focus();
}

function myopacApplyThawDate() {
    var dateString = dojo.date.stamp.toISOString(dijit.byId('myopac_holds_thaw_date_input').getValue());
    if(dateString) {
        dateString = holdsVerifyThawDate(dateString);
        if(!dateString) return;
    } else {
        dateString = null;
    }
    myopacProcessHolds('freeze', dateString);
}

function myopacHoldIDFromRow(row) {
    return row.id.replace(/.*_(\d+)$/, '$1');
}

function myopacShowHoldProcessing() {
    unHideMe($('myopac_holds_processing'));
    hideMe($('myopac_holds_main_table'));
}

function myopacHideHoldProcessing() {
    hideMe($('myopac_holds_processing'));
    unHideMe($('myopac_holds_main_table'));
    hideMe($('myopac_holds_thaw_date_form'));
}

function myopacBatchHoldCallback(r) {
    if(r) /* force load any exceptions */
        r.getResultObject();
    if(++myopacProcessedHolds >= myopacHoldsToProcess.length) {
        myopacHideHoldProcessing();
        holdCache = {};
        holdStatusCache = {};
        myopacForceHoldsRedraw = true;
        myOPACShowHolds();
    }
}

