var holdsOrgSelectorBuilt = false;
var holdArgs;



function holdsHandleStaff() {
	swapCanvas($('xulholds_box'));
	$('xul_recipient_barcode').focus();
	$('xul_recipient_barcode').onkeypress = function(evt) 
		{if(userPressedEnter(evt)) { _holdsHandleStaff(); } };
	$('xul_recipient_barcode_submit').onclick = _holdsHandleStaff;
	$('xul_recipient_me').onclick = _holdsHandleStaffMe;
}

function _holdsHandleStaffMe() {
	holdArgs.recipient = G.user;
	holdsDrawEditor();
}

function _holdsHandleStaff() {
	var barcode = $('xul_recipient_barcode').value;
	var user = grabUserByBarcode( G.user.session, barcode );
	if(!user) return;
	holdArgs.recipient = user;
	holdsDrawEditor();
}


/** args:
  * record, volume, copy (ids)
  * request, recipient, editHold (objects)
  */
function holdsDrawEditor(args) {

	holdArgs = (args) ? args : holdArgs;

	if(isXUL() && holdArgs.recipient == null 
			&& holdArgs.editHold == null) {
		holdsHandleStaff();
		return;
	}

	if(!holdArgs.recipient) holdArgs.recipient = G.user;
	if(!holdArgs.requestor) holdArgs.requestor = G.user;

	if(!(holdArgs.requestor && holdArgs.requestor.session)) {
		detachAllEvt('common','locationChanged');
		attachEvt('common','loggedIn', holdsDrawEditor)
		initLogin();
		return;
	}

	if(holdArgs.editHold) /* flesh the args with the existing hold */
		holdArgsFromHold(holdArgs.editHold, holdArgs);

	holdsDrawWindow();

	if(holdArgs.editHold) {
		hideMe($('holds_submit'));
		unHideMe($('holds_update'));
		var req = new Request(FETCH_HOLD_STATUS, 
			G.user.session, holdArgs.editHold.id());
		req.send(true);
		holdArgs.status = req.result();
		_holdsUpdateEditHold();
	}  

}


/* updates the edit window with the existing hold's data */
function _holdsUpdateEditHold() {

	var hold = holdArgs.editHold;
	var status = holdArgs.status;

	var orgsel = $('holds_org_selector');
	setSelector(orgsel, hold.pickup_lib());

	if( hold.capture_time() || status > 2 )
		orgsel.disabled = true;
	else	
		orgsel.disabled = false;


	$('holds_submit').onclick = holdsEditHold;
	$('holds_update').onclick = holdsEditHold;

	if(hold.phone_notify()) {
		$('holds_enable_phone').checked = true;
		$('holds_phone').value = hold.phone_notify();

	} else {
		$('holds_phone').disabled = true;
		$('holds_enable_phone').checked = false;
	}

	if(hold.email_notify()) {
		$('holds_enable_email').checked = true;

	} else {
		$('holds_enable_email').checked = false;
	}
}

function holdsEditHold() {
	var hold = holdsBuildHoldFromWindow();
	if(!hold) return;
	holdsUpdate(hold);
	showCanvas();
	if(holdArgs.onComplete)
		holdArgs.onComplete(hold);
}

function holdArgsFromHold(hold, oargs) {
	var args = (oargs) ? oargs : {};
	args.type = hold.hold_type();
	var target = hold.target();

	switch(args.type) {
		case 'M':
			args.metarecord = target;
			break;
		case 'T':
			args.record = target;
			break;
		case 'V':
			args.volume = target;
			break;
		case 'C':
			args.copy = target;
			break;
	}
	return args;
}

function holdFetchObjects(hold, doneCallback) {

	var args = (hold) ? holdArgsFromHold(hold) : holdArgs;

	var type = args.type;

	if( type == 'C' ) {

		if( args.copyObject ) {

			args.copy = args.copyObject.id();
			args.volume = args.copyObject.call_number();
			_h_set_vol(args, doneCallback);

		} else {
			var creq = new Request(FETCH_COPY, args.copy);

			creq.callback(
				function(r) {
					var cp = r.getResultObject();
					args.copyObject = cp;
					args.volume = args.copyObject.call_number();
					_h_set_vol(args, doneCallback);
				}
			);
			creq.send();
		}
	} else {
		if( type == 'V' ) {
			_h_set_vol(args, doneCallback);

		} else {
			if( type == 'T' ) {
				_h_set_rec(args, doneCallback);
			}
		}
	}

	return args;
}

function _h_set_vol(args, doneCallback) {

	if( args.volumeObject ) {
		args.volume = args.volumeObject.id();
		args.record = args.volumeObject.record();
		_h_set_rec(args, doneCallback);

	} else {

		var vreq = new Request(FETCH_VOLUME, args.volume);
		vreq.callback(
			function(r) {
				var vol = r.getResultObject();
				args.volumeObject = vol;
				args.record = vol.record();
				_h_set_rec(args, doneCallback);
			}
		);
		vreq.send();
	}
}

function _h_set_rec(args, doneCallback) {
	if(args.recordObject) {
		args.record = args.recordObject.doc_id();
	} else {
		args.recordObject = findRecord( args.record, 'T' );
	}
	if(doneCallback) doneCallback(args);
}



function holdsDrawWindow() {
	swapCanvas($('holds_box'));
	$('holds_cancel').onclick = function(){ runEvt('common', 'holdUpdateCanceled'), showCanvas() };
	$('holds_submit').onclick = function(){holdsPlaceHold(holdsBuildHoldFromWindow())};
	$('holds_update').onclick = function(){holdsPlaceHold(holdsBuildHoldFromWindow())};
	holdFetchObjects(null, function(){__holdsDrawWindow();});
}

function __holdsDrawWindow() {

	var rec = holdArgs.recordObject;
	var vol = holdArgs.volumeObject;
	var copy = holdArgs.copyObject;

	if(!holdsOrgSelectorBuilt) {
		holdsBuildOrgSelector(null,0);
		holdsOrgSelectorBuilt = true;
	}

	if(isXUL()) {
		var dsel = $('holds_depth_selector');
		unHideMe($('holds_depth_selector_row'));
		if(dsel.getElementsByTagName('option').length == 0) {
			var types = globalOrgTypes;
			var depth = findOrgDepth(G.user.ws_ou());
			iterate(types, 
				function(t) {
					if(t.depth() > depth) return;
					insertSelectorVal(dsel, -1, t.opac_label(), t.depth());
				}
			);
		}
	}

	appendClear($('holds_recipient'), text(
		holdArgs.recipient.family_name() + ', ' +  
			holdArgs.recipient.first_given_name()));
	appendClear($('holds_title'), text(rec.title()));
	appendClear($('holds_author'), text(rec.author()));

	if( holdArgs.type == 'V' || holdArgs.type == 'C' ) {

		unHideMe($('holds_type_row'));
		unHideMe($('holds_cn_row'));
		appendClear($('holds_cn'), text(holdArgs.volumeObject.label()));

		if( holdArgs.type == 'V'  ) {
			unHideMe($('holds_is_cn'));
			hideMe($('holds_is_copy'));

		} else {
			hideMe($('holds_is_cn'));
			unHideMe($('holds_is_copy'));
			unHideMe($('holds_copy_row'));
			appendClear($('holds_copy'), text(holdArgs.copyObject.barcode()));
		}

	} else {
		hideMe($('holds_type_row'));
		hideMe($('holds_copy_row'));
		hideMe($('holds_cn_row'));
	}

	removeChildren($('holds_format'));
	for( var i in rec.types_of_resource() ) {
		var res = rec.types_of_resource()[i];
		var img = elem("img");
		setResourcePic(img, res);
		$('holds_format').appendChild(text(' '+res+' '));
		$('holds_format').appendChild(img);
		$('holds_format').appendChild(text(' '));
	}


	$('holds_phone').value = holdArgs.recipient.day_phone();
	appendClear( $('holds_email'), text(holdArgs.recipient.email()));

	var pref = G.user.prefs[PREF_HOLD_NOTIFY];

	if(pref) {
		if( ! pref.match(/email/i) ) 
			$('holds_enable_email').checked = false;

		if( ! pref.match(/phone/i) ) {
			$('holds_phone').disabled = true;
			$('holds_enable_phone').checked = false;
		}
	}

	appendClear($('holds_physical_desc'), text(rec.physical_description()));
	if(holdArgs.type == 'M') hideMe($('hold_physical_desc_row'));
}


function holdsCheckPossibility(pickuplib) {
	var rec = holdArgs.record;
	var type = holdArgs.type;
	var req = new Request(CHECK_HOLD_POSSIBLE, G.user.session, 
			{ titleid : rec, patronid : G.user.id(), depth : 0, pickup_lib : pickuplib } );
	req.send(true);
	return req.result();
}


function holdsBuildOrgSelector(node) {

	if(!node) node = globalOrgTree;

	var selector = $('holds_org_selector');
	var index = selector.options.length;

	var type = findOrgType(node.ou_type());
	var indent = type.depth() - 1;
	var opt = setSelectorVal( selector, index, node.name(), node.id(), null, indent );
	if(!type.can_have_vols()) opt.disabled = true;
	
	if( node.id() == holdArgs.recipient.home_ou() ) {
		selector.selectedIndex = index;
		selector.options[index].selected = true;	
	}

	for( var i in node.children() ) {
		var child = node.children()[i];
		if(child) holdsBuildOrgSelector(child);
	}
}

function holdsBuildHoldFromWindow() {

	var org = $('holds_org_selector').options[
		$('holds_org_selector').selectedIndex].value;

	var hold = new ahr();
	if(holdArgs.editHold) {
		hold = holdArgs.editHold;
		holdArgs.editHold = null;
	}

	if( $('holds_enable_phone').checked ) {
		var phone = $('holds_phone').value;
		if( !phone || !phone.match(REGEX_PHONE) ) {
			alert($('holds_bad_phone').innerHTML);
			return null;
		}
		hold.phone_notify(phone);

	} else {
		hold.phone_notify("");
	}

	if( $('holds_enable_email').checked ) 
		hold.email_notify(1);
	else
		hold.email_notify(0);

	var target;

	switch(holdArgs.type) {
		case 'M':
			target = holdArgs.metarecord;
			break;
		case 'T':
			target = holdArgs.record;
			break;
		case 'V':
			target = holdArgs.volume;
			break;
		case 'C':
			target = holdArgs.copy;
			break;
	}


	hold.pickup_lib(org); 
	hold.request_lib(org); 
	hold.requestor(holdArgs.requestor.id());
	hold.usr(holdArgs.recipient.id());
	hold.hold_type(holdArgs.type);
	hold.target(target);

	if(isXUL())		
		hold.selection_depth(getSelectorVal($('holds_depth_selector')));
	return hold;
}
	
function holdsPlaceHold(hold) {

	if(!hold) return;

	swapCanvas($('check_holds_box'));

	if( holdArgs.type == 'M' || holdArgs.type == 'T' ) {
		if( ! holdsCheckPossibility(hold.pickup_lib() ) ) {
			alert($('hold_not_allowed').innerHTML);
			swapCanvas($('holds_box'));
			return;
		}
	}

	var req = new Request( CREATE_HOLD, holdArgs.requestor.session, hold );
	req.send(true);
	var res = req.result();

	if( res == '1' ) alert($('holds_success').innerHTML);
	else alert($('holds_failure').innerHTML);
	
	showCanvas();

	holdArgs = null;
	runEvt('common', 'holdUpdated');
}

function holdsCancel(holdid, user) {
	if(!user) user = G.user;
	var req = new Request(CANCEL_HOLD, user.session, holdid);
	req.send(true);
	return req.result();
	runEvt('common', 'holdUpdated');
}

function holdsUpdate(hold, user) {
	if(!user) user = G.user;
	var req = new Request(UPDATE_HOLD, user.session, hold);
	req.send(true);
	var x = req.result(); /* cause an exception if there is one */
	runEvt('common', 'holdUpdated');
}




