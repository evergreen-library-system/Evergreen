var holdsOrgSelectorBuilt = false;
var holdArgs;

/* 
note: metarecord holds have a holdable_formats field that contains
item_type(s)-item_forms(s)-language
item_form and language are optional - if language exist and no 
item_form is specified, use item_type(s)--language
*/

var noEmailMessage;
var noEmailMessageXUL;

var holdTargetTypeMap = {
    M : 'metarecord',
    T : 'record',
    V : 'volume',
    I : 'issuance',
    C : 'copy',
    P : 'part'
};



function holdsHandleStaff() {

    // if we know the recipient's barcode, use it
    if(xulG.patron_barcode) return _holdsHandleStaff();

	swapCanvas($('xulholds_box'));
	$('xul_recipient_barcode').focus();
	$('xul_recipient_barcode').onkeypress = function(evt) 
		{if(userPressedEnter(evt)) { _holdsHandleStaff(); } };
	$('xul_recipient_barcode_submit').onclick = _holdsHandleStaff;
	$('xul_recipient_me').onclick = _holdsHandleStaffMe;

	$('xul_recipient_barcode').onkeyup = function(evt) {
        if($('xul_recipient_barcode').value == '') 
            $('xul_recipient_me').disabled = false;
        else
            $('xul_recipient_me').disabled = true;
    };
}

$('holds_frozen_thaw_input').onchange = 
        function(){holdsVerifyThawDateUI('holds_frozen_thaw_input');}
$('holds_frozen_thaw_input').onkeyup = 
        function(){holdsVerifyThawDateUI('holds_frozen_thaw_input');}

function _holdsHandleStaffMe() {
	holdArgs.recipient = G.user;
	holdsDrawEditor();
}

function _holdsHandleStaff() {
	var barcode = xulG.patron_barcode;
    if(!barcode) {
        barcode = $('xul_recipient_barcode').value;
        if(xulG.get_barcode) {
            // We have a "complete the barcode" function, call it (actor = users only)
            var new_barcode = xulG.get_barcode(window, 'actor', barcode);
            // If we got a result (boolean false is "no result") check it
            if(new_barcode) {
                // user_false string means they picked "None of the above"
                // Abort before any other events can fire
                if(new_barcode == "user_false") return;
                // No error means we have a (hopefully valid) completed barcode to use.
                // Otherwise, fall through to other methods of checking
                if(typeof new_barcode.ilsevent == 'undefined')
                    barcode = new_barcode.barcode;
            }
        }
    }
	var user = grabUserByBarcode( G.user.session, barcode );

	var evt;
	if(evt = checkILSEvent(user)) {
		alertILSEvent(user);
		return;
	}

	if(!barcode || !user) {
		alertId('holds_invalid_recipient', barcode);
		return
	}

	grabUserPrefs(user);

	holdArgs.recipient = user;
	holdsDrawEditor();
}



/** args:
  * record, volume, copy (ids)
  * request, recipient, editHold (objects)
  */

function holdsDrawEditor(args) {

	holdArgs = (args) ? args : holdArgs;

    if(!noEmailMessage)
        noEmailMessage = $('holds_email').removeChild($('holds.no_email'));

    if(!noEmailMessageXUL)
        noEmailMessageXUL = $('holds_email').removeChild($('holds.no_email.xul'));

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

	if(holdArgs.editHold) // flesh the args with the existing hold 
		holdArgsFromHold(holdArgs.editHold, holdArgs);

     removeCSSClass($('holds_parts_selector'), 'parts-warning');
    holdArgs.partsSuggestionMade = false;

	holdsDrawWindow();
}


// updates the edit window with the existing hold's data 
function _holdsUpdateEditHold() {

	var hold = holdArgs.editHold;
	var qstats = holdArgs.status;

	var orgsel = $('holds_org_selector');
    var frozenbox = $('holds_frozen_chkbox');

	setSelector(orgsel, hold.pickup_lib());

	if( hold.capture_time() || qstats.status > 2 ) {
        frozenbox.disabled = true;
        $('holds_frozen_thaw_input').disabled = true;
        if(qstats.status == 3) {
            // no pickup lib changes while in-transit
		    orgsel.disabled = true;
        } else {
            var orgs = fetchPermOrgs('UPDATE_PICKUP_LIB_FROM_HOLDS_SHELF');
            if(orgs[0] == -1)
		        orgsel.disabled = true;
        }
    } else {
		orgsel.disabled = false;
        frozenbox.disabled = false;
    }


	$('holds_submit').onclick = holdsEditHold;
	$('holds_update').onclick = holdsEditHold;

	if(hold.phone_notify()) {
		$('holds_enable_phone').checked = true;
		$('holds_phone').value = hold.phone_notify();

	} else {
		$('holds_phone').disabled = true;
		$('holds_enable_phone').checked = false;
	}

	if(isTrue(hold.email_notify())) {
		$('holds_enable_email').checked = true;

	} else {
		$('holds_enable_email').checked = false;
	}

    dijit.byId('holds_expire_time').setValue(dojo.date.stamp.fromISOString(hold.expire_time()));

    /* populate the hold freezing info */
    if(!frozenbox.disabled && isTrue(hold.frozen())) {
        frozenbox.checked = true;
        unHideMe($('hold_frozen_thaw_row'));
        if(hold.thaw_date()) {
            dijit.byId('holds_frozen_thaw_input').setValue(dojo.date.stamp.fromISOString(hold.thaw_date()));
        } else {
            dijit.byId('holds_frozen_thaw_input').setValue('');
        }
    } else {
        frozenbox.checked = false;
        dijit.byId('holds_frozen_thaw_input').setValue('');
        hideMe($('hold_frozen_thaw_row'));
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
    args[holdTargetTypeMap[args.type]] = target;
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

        } else if( type == 'I' ) {
            _h_set_issuance(args, doneCallback);

        } else if( type == 'P' ) {
            _h_set_parts(args, doneCallback);

		} else {
			if( type == 'T') {
				_h_set_rec(args, doneCallback);
			} else {
				_h_set_rec_descriptors(args, doneCallback);
			}
		}
	}

	return args;
}

function _h_set_parts(args, doneCallback) {

    var preq = new Request(
        'open-ils.fielder:open-ils.fielder.bmp.atomic',
        {"cache":1, "fields":["label", "record"],"query": {"id":args.part}}
    );

    preq.callback(
        function(r) {
            var part = r.getResultObject()[0];
            args.record = part.record;
            args.partObject = part;
            _h_set_rec(args, doneCallback);
        }
    );

    preq.send();
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

function _h_set_issuance(args, doneCallback) {

	if( args.issuanceObject ) {
		args.issuance = args.issuanceObject.id();
		args.record = args.issuanceObject.subscription().record_entry();
		_h_set_rec(args, doneCallback);

	} else {

		var vreq = new Request(FETCH_ISSUANCE, [args.issuance]);
		vreq.callback(
			function(r) {
				var issuance = r.getResultObject()[0];
				args.issuanceObject = issuance;
				args.record = issuance.subscription().record_entry();
				_h_set_rec(args, doneCallback);
			}
		);
		vreq.send();
	}
}

function _h_set_rec(args, doneCallback) {

	if(args.recordObject) 
		args.record = args.recordObject.doc_id();
	else 
		args.recordObject = findRecord( args.record, 'T' );
	
	if( args.type == 'T' || args.type == 'M' )  {
		_h_set_rec_descriptors(args, doneCallback);
	//} else if(args.type == 'P') {
        //_h_get_parts(args, doneCallback);
    } else {
		if(doneCallback) doneCallback(args);
    }
}


function _h_set_rec_descriptors(args, doneCallback) {

    if( ! args.pickup_lib )
        args.pickup_lib = getSelectorVal($('holds_org_selector'));

    if(args.pickup_lib === null)
        args.pickup_lib = args.recipient.home_ou();

	// grab the list of record desciptors attached to this records metarecord 
	if( ! args.recordDescriptors )  {
		var params = { pickup_lib: args.pickup_lib };

        if (args.type == 'M') {
    		if( !args.metarecord && args.record) {
                params.metarecord = args.metarecord = args.record;
                delete(args.record);
	    	} else {
		    		params.metarecord = args.metarecordObject.doc_id();
    		}
        } else {
    		params.record = args.record;
        }

		if( ! args.record ) {
			if( args.metarecord )
				params.metarecord = args.metarecord;
			else 
				params.metarecord = args.metarecordObject.doc_id();
		}

		var req = new Request(FETCH_MR_DESCRIPTORS, params );
		req.callback(
			function(r) {
				var data = r.getResultObject();
				args.recordDescriptors = args.recordDescriptors = data.descriptors;
				args.metarecord = args.metarecord = data.metarecord;
				if( args.type == 'M' && ! args.metarecordObject) 
					args.metarecordObject = args.metarecordObject = findRecord(args.metarecord, 'M');	

                _h_get_parts(args, doneCallback);
			}
		);
		req.send();

	} else {
        _h_get_parts(args, doneCallback);
	}

	return args;
}

function _h_get_parts(args, doneCallback) {

    if(args.type == 'M' || args.editHold || args.holdParts) {
        if(doneCallback) 
            doneCallback(args);

    } else {

		var req = new Request(
            'open-ils.search:open-ils.search.biblio.record_hold_parts', 
		    {pickup_lib: args.pickup_lib, record: args.record}
        );

		req.callback(
			function(r) {
				args.recordParts = r.getResultObject();
                if(doneCallback)
                    doneCallback(args);
			}
		);
		req.send();
    }
}



function holdsDrawWindow() {
	swapCanvas($('holds_box'));
	$('holds_cancel').onclick = function(){ runEvt('common', 'holdUpdateCanceled'), showCanvas() };
	$('holds_submit').onclick = function(){holdsPlaceHold(holdsBuildHoldFromWindow())};
	$('holds_update').onclick = function(){holdsPlaceHold(holdsBuildHoldFromWindow())};
	holdFetchObjects(null, 
		function(){
			__holdsDrawWindow();

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
	);
}

function __holdsDrawWindow() {

	var rec = holdArgs.recordObject;
	var vol = holdArgs.volumeObject;
	var copy = holdArgs.copyObject;
	var mr = holdArgs.metarecordObject;

	rec = (rec) ? rec : mr;

	if(!holdsOrgSelectorBuilt) {
		holdsBuildOrgSelector(null,0);
		holdsOrgSelectorBuilt = true;
		var selector = $('holds_org_selector');

		/*
		var o_loc = findOrgUnit(getOrigLocation());
		var t = findOrgType(o_loc.ou_type());
		if( t.can_have_users() ) 
			setSelector(selector, o_loc.id());
		else 
		*/

		setSelector(selector, holdArgs.recipient.home_ou());
	
	}

	/*
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
	*/

	appendClear($('holds_recipient'), text(
		holdArgs.recipient.family_name() + ', ' +  
			holdArgs.recipient.first_given_name()));
	appendClear($('holds_title'), text(rec.title()));
	appendClear($('holds_author'), text(rec.author()));

    if( holdArgs.type == 'I' ) {
		unHideMe($('holds_type_row'));
        unHideMe($('holds_is_issuance'));
        unHideMe($('holds_issuance_row'));
        appendClear($('holds_issuance_label'), text(holdArgs.issuanceObject.label()));

    } else if( holdArgs.type == 'V' || holdArgs.type == 'C' ) {

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
		hideMe($('holds_issuance_row'));
	}

    if(holdArgs.recordParts && holdArgs.recordParts.length) {
        var selector = $('holds_parts_selector');
        unHideMe($('holds_parts_row'));
        unHideMe(selector);

        var nodeList = [];
        dojo.forEach(selector.options, 
            function(node) { if(node.value != '') nodeList.push(node) } );

        dojo.forEach(nodeList, function(node) { selector.removeChild(node); });

        dojo.forEach(
            holdArgs.recordParts, 
            function(part) {
                insertSelectorVal(selector, -1, part.label, part.id);
            }
        );

    } else if(holdArgs.type == 'P') {
        unHideMe($('holds_parts_row'));
        unHideMe($('holds_parts_label'));
	    appendClear( $('holds_parts_label'), text(holdArgs.partObject.label));
    }

	removeChildren($('holds_format'));

	var mods_formats = rec.types_of_resource();
	var formats;

	if (holdArgs.recordDescriptors && holdArgs.recordDescriptors.length)
		formats = holdArgs.recordDescriptors[0].item_type();

	if( holdArgs.type == 'T' ) {
		var desc = grep( holdArgs.recordDescriptors,
			function(i) {
				return (i.record() == holdArgs.record);	
			}
		);
		if (desc) {
			formats = desc[0].item_type();
		}
	}

	if( holdArgs.type == 'M' ) {
		var mr_formats;
		if(holdArgs.editHold){
			mr_formats = holdArgs.editHold.holdable_formats();
		}else{
			mr_formats = ''; // collect the item_type()s from all holdArgs.recordDescriptors
			for(var desc in holdArgs.recordDescriptors){
                if (!holdArgs.recordDescriptors[desc].item_type()) continue;
				mr_formats += holdArgs.recordDescriptors[desc].item_type();
			}

            var first_form = 1;
			for(var desc in holdArgs.recordDescriptors){
                if (!holdArgs.recordDescriptors[desc].item_form()) continue;
                if (first_form) {
                    mr_formats += '-';
                    first_form = 0;
                }
				mr_formats += holdArgs.recordDescriptors[desc].item_form();
			}


		}
		
		var data = holdsParseMRFormats(mr_formats);
		mods_formats = data.mods_formats;
		formats = data.formats;
	}


	for( var i in mods_formats ) {
		var res = mods_formats[i];
		var img = elem("img");
		setResourcePic(img, res);
		$('holds_format').appendChild(img);
		if(formats)
			$('holds_format').appendChild(text(' '+ MARCTypeToFriendly(formats[i]) +' '));
		else
			$('holds_format').appendChild(text(' '+ mods_formats[i] +' '));
		$('holds_format').appendChild(elem('br'));
	}


	$('holds_phone').value = holdArgs.recipient.day_phone();
	appendClear( $('holds_email'), text(holdArgs.recipient.email()));

	var pref = holdArgs.recipient.prefs[PREF_HOLD_NOTIFY];

	if(pref) {
		if( ! pref.match(/email/i) ) {
			$('holds_enable_email').checked = false;
		} else {
			$('holds_enable_email').checked = true;
		}

		if( ! pref.match(/phone/i) ) {
			$('holds_phone').disabled = true;
			$('holds_enable_phone').checked = false;
		} else {
			$('holds_phone').disabled = false;
			$('holds_enable_phone').checked = true;
		}
	}

    if(!holdArgs.recipient.email()) {
		$('holds_enable_email').checked = false;	
		$('holds_enable_email').disabled = true;
        var message;
        if(isXUL()) {
            message = noEmailMessageXUL.cloneNode(true);
	        appendClear($('holds_email'), message);
        } else {
            message = noEmailMessage.cloneNode(true);
	        appendClear($('holds_email'), message);
            $('holds.no_email.my_account').setAttribute('href', buildOPACLink({page:MYOPAC},null,true));
        }
        unHideMe(message);
    }

	if(!$('holds_phone').value) 
		$('holds_enable_phone').checked = false;	

	appendClear($('holds_physical_desc'), text(rec.physical_description()));

	if(holdArgs.type == 'M') hideMe($('hold_physical_desc_row'));

	holdsSetFormatSelector();

    $('holds_frozen_chkbox').checked = false;
    hideMe($('hold_frozen_thaw_row'));

    var interval = fetchOrgSettingDefault(holdArgs.recipient.home_ou(), 'circ.hold_expire_interval');
    var secs = 0;
    if(interval) {
        secs = interval_to_seconds(interval);
        var expire = new Date();
        expire.setTime(expire.getTime() + Number(secs + '000'));
        dijit.byId('holds_expire_time').setValue(expire);
    }
}

function holdsParseMRFormats(str) {
	var data = str.split(/-/);	

	var formats = [];
	var mods_formats = [];

	for( var i = 0; i < data[0].length; i++ ) {
		formats.push( data[0].charAt(i) );
		mods_formats.push( MARCFormatToMods( formats[i] ) );
	}
	
	formats = uniquify(formats);
	mods_formats = uniquify(mods_formats);

	return {
		formats			: formats,
		mods_formats	: mods_formats,
		lang				: data[2],
		largeprint		: data[1]
	};
}


function holdsSetFormatSelector() {
	var type = holdArgs.type;
	if( type == 'C' || type == 'V' || type == "I" || holdArgs.editHold ) return;

	var data				= holdsGetFormats();
	var avail_formats	= data.avail_formats;
	var sel_formats	= data.sel_formats;
	holdArgs.language = data.lang;
	if( type=='M'){		
		hideMe($('holds_alt_formats_row_extras'));
		unHideMe($('holds_alt_formats_row'));	
	}else{
		unHideMe($('holds_alt_formats_row_extras'));
	}

	var selector = $('hold_alt_form_selector');

    for( var i = 0; i < selector.options.length; i++ ) {
        if (selector.options[i].className.indexOf('hide_me') == -1)
            hideMe(selector.options[i]);
        selector.options[i].disabled = true;
    }

	for( var i = 0; i < avail_formats.length; i++ ) {
		var form = avail_formats[i];
		var opt = findFormatSelectorOptByParts(selector,form);
        if (!opt) continue;
		if(type=='M') opt.selected=true;
		unHideMe(opt);
        opt.disabled = false;
	}

    // If the user selects a format, P-type holds are no longer an option
    // disable and reset the P-type form control
    selector.onchange = function() {
        var partsSel = $('holds_parts_selector');
        for(var i = 0; i < selector.options.length; i++) {
            if(selector.options[i].selected) {
                partsSel.selectedIndex = 0; // none selected
                partsSel.disabled = true;
                return;
            }
        }
        partsSel.disabled = false;
    }
}

function findFormatSelectorOptByParts( sel, val ) {
    var parts = val.split('-');
    for( var i = 0; i < sel.options.length; i++ ) {
        var opt = sel.options[i];
        var oval = opt.value;
        var oparts = oval.split('-');
        if( oparts[0].indexOf(parts[0]) > -1 && (!parts[1] || oparts[1].indexOf(parts[1]) > -1) ) return opt;
    }
    return null;
}

function holdsGetFormats() {

	var lang;
	var formats = [];
	var sformats = []; // selected formats 

	var type = holdArgs.type;
	var desc = holdArgs.recordDescriptors;
	var rec	= holdArgs.record;
	var mrec = holdArgs.metarecord;


	if( type == 'T') {

		for( var i = 0; i < desc.length; i++ ) {
			var d = desc[i];
			if( d.record() == holdArgs.record ) {
				lang = d.item_lang();
				holdArgs.myFormat =  _t_f_2_format(d.item_type(), d.item_form());
				sformats.push(holdArgs.myFormat);
				break;
			}
		}

    	for( var i = 0; i < desc.length; i++ ) {
	    	var d = desc[i];
		    if( type == 'T' && d.item_lang() != lang ) continue;
    		formats.push( _t_f_2_format(d.item_type(), d.item_form()));
	    }

	} else if( type =='M') {

        // All available formats are selected by default in MR holds
       	for( var i = 0; i < desc.length; i++ ) {
	    	var d = desc[i];
		    var _tmp_f = _t_f_2_format(d.item_type(), d.item_form());
    		formats.push( _tmp_f );
	    	sformats.push( _tmp_f );
    	}
	}

	formats = uniquify(formats);
	sformats = uniquify(sformats);

	return {
		lang : lang,
		avail_formats : formats, 
		sel_formats : sformats
	};
}



function _t_f_2_format(type, form) {
	if( (type == 'a' || type == 't') && form == 's' ) return 'at-s';
	if( form == 'd' ) return 'at-d';
	return (type == 'a' || type == 't') ? 'at' : type;
}

function holdsSetSelectedFormats() {

	var cn = $('holds_alt_formats_row').className;
	if( cn && cn.match(/hide_me/) ) return;

	var selector = $('hold_alt_form_selector');
	var vals = getSelectedList(selector);

	if(vals.length == 0) return;

	var fstring = "";

	if( contains(vals, 'at-d') || contains(vals, 'at-s') || contains(vals, 'at')) {
		if( contains(vals, 'at') ) {
			fstring = 'at';
		} else if (contains(vals, 'at-s') && contains(vals, 'at-d')) {
			fstring = 'at-sd';
		} else if (!contains(vals, 'at-s')) {
			fstring = 'at-d';
		} else {
			fstring = 'at-s';
		}
	}

	for( var i = 0; i < vals.length; i++ ) {
		var val = vals[i];
		if( !val.match(/at/) ) fstring = val + fstring;
	}

	if( holdArgs.language ) {
		if( fstring.match(/-/) )
			fstring = fstring + '-' + holdArgs.language;
		else
			fstring = fstring + '--' + holdArgs.language;
	}


	return fstring;
}


function holdsCheckPossibility(pickuplib, hold, recurse) {

	var args = { 
		titleid : holdArgs.record,
		mrid : holdArgs.metarecord,
		volume_id : holdArgs.volume,
		issuanceid : holdArgs.issuance,
		copy_id : holdArgs.copy,
		hold_type : holdArgs.type,
		holdable_formats : holdArgs.holdable_formats,
		patronid : holdArgs.recipient.id(),
		depth : 0, 
		pickup_lib : pickuplib,
        partid : holdArgs.part
	};

	if(recurse) {
		/* if we're calling create again (recursing), 
			we know that the hold possibility check already succeeded */
		holdHandleCreateResponse({_recurse:true, _hold:hold}, true );

	} else {
		_debug("hold possible args = "+js2JSON(args));
	
		var req = new Request(CHECK_HOLD_POSSIBLE, G.user.session, args );
	
		req.request.alertEvent = false;
		req.request._hold = hold;
		req.request._recurse = recurse;
		req.callback(holdHandleCreateResponse);
		req.send();
	}
}


function holdsBuildOrgSelector(node) {

	if(!node) node = globalOrgTree;
	if(!isTrue(node.opac_visible()) && !isXUL()) return;

	var render_this_org = true;
	var orgHiding = checkOrgHiding(); // value here is cached so not too painful with the recursion
	if (orgHiding) {
		if (node.id() == globalOrgTree.id()) {
			node = orgHiding.org; // top of tree = org hiding context org
		}
		if ( ! orgIsMine( orgHiding.org, node, orgHiding.depth ) ) {
			render_this_org = false;
		}
	}

	if (render_this_org) {
		var selector = $('holds_org_selector');
		var index = selector.options.length;

		var type = findOrgType(node.ou_type());
		var indent = type.depth() - 1;

		var opt = setSelectorVal( selector, index, node.name(), node.id(), null, indent );
		if(!type.can_have_users()) {
			opt.disabled = true;
			addCSSClass(opt, 'disabled_option');
		}
	}
	
	for( var i in node.children() ) {
		var child = node.children()[i];
		if(child) holdsBuildOrgSelector(child);
	}
}

function holdsBuildHoldFromWindow() {

	var org = getSelectorVal($('holds_org_selector'));
	var node = findOrgUnit(org);
	var ntype = findOrgType(node.ou_type());
	if(!ntype.can_have_users()) {
		alertId('holds_pick_good_org');
		return;
	}

    fieldmapper.IDL.load(['ahr']);
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

    var part = getSelectorVal($('holds_parts_selector'));
    if(part) {
        holdArgs.type = 'P';
        holdArgs.part = part;
    }

	var target = holdArgs[holdTargetTypeMap[holdArgs.type]];

    // a mono part is selected

	hold.pickup_lib(org); 
	//hold.request_lib(org); 
	hold.requestor(holdArgs.requestor.id());
	hold.usr(holdArgs.recipient.id());
	hold.target(target);
	hold.hold_type(holdArgs.type);

    var expDate = dijit.byId('holds_expire_time').getValue();
    if(expDate) {
        var expireDate = dojo.date.stamp.toISOString(expDate);
        expireDate = holdsVerifyThawDate(expireDate); 
        if(expireDate)
            hold.expire_time(expireDate);
        else 
            return;
    }

    // see if this hold should be frozen and for how long
    if($('holds_frozen_chkbox').checked) {
        hold.frozen('t');
        unHideMe($('hold_frozen_thaw_row'));
        var thawDate = dijit.byId('holds_frozen_thaw_input').attr('value');
        if(thawDate) {
            thawDate = dojo.date.stamp.toISOString(thawDate);
            thawDate = holdsVerifyThawDate(thawDate); 
            if(thawDate) 
                hold.thaw_date(thawDate);
            else
                return;
        } else {
            hold.thaw_date(null);
        }
    } else {
        hold.frozen('f');
        hold.thaw_date(null);
    }

	//check for alternate hold formats 
	var fstring = holdsSetSelectedFormats();
	if(fstring) { 
		hold.hold_type('M'); 
		hold.holdable_formats(fstring);
		if (fstring)
			holdArgs.holdable_formats = fstring;
		hold.target(holdArgs.metarecord);
	}
	return hold;
}
	
function holdsPlaceHold(hold, recurse) {
	if(!hold) return;
	swapCanvas($('check_holds_box'));
	holdsCheckPossibility(hold.pickup_lib(), hold, recurse);
}


function holdHandleCreateResponse(r, recurse) {

	if(!recurse) {
		var res = r.getResultObject();
        var age_protect_override = false;;
		if(checkILSEvent(res) || res.success != 1) {
            if(res.success != 1 && res.age_protected_copy == 1) {
                // There is at least one copy that *could* fill the hold, if it were not age-protected.
                if( confirm($('hold_age_protected_override').innerHTML) ) {
                    age_protect_override = true;
                } else {
    		    	swapCanvas($('holds_box'));
	    		    return;
                }
            }
            if(!age_protect_override) {
    			if(res.success != 1) {

                    if(!holdArgs.partsSuggestionMade && holdArgs.recordParts && 
                            holdArgs.recordParts.length && holdArgs.type == 'T') {
                        // T holds on records that have parts are OK, but if the record has no non-part
                        // copies, the hold will ultimately fail.  Suggest selecting a part to the user.
                        addCSSClass($('holds_parts_selector'), 'parts-warning');
                        holdArgs.partsSuggestionMade = true;
                        alert($('hold_has_parts').innerHTML);
                    } else {
			    	    alert($('hold_not_allowed').innerHTML);
                    }
    			} else {
	    			if( res.textcode == 'PATRON_BARRED' ) {
		    			alertId('hold_failed_patron_barred');
			    } else {
				    	alert($('hold_not_allowed').innerHTML);
    				}
	    		}
		    	swapCanvas($('holds_box'));
			    return;
            }
		}
        r._hold.selection_depth(res.depth);
	}	

	holdCreateHold(r._recurse, r._hold);
}


function holdCreateHold( recurse, hold ) {
	var method = CREATE_HOLD;
	if(recurse) method = CREATE_HOLD_OVERRIDE;
	var req = new Request( method, holdArgs.requestor.session, hold );
	req.request.alertEvent = false;
	req.send(true);
	var res = req.result();
	holdProcessResult(hold, res, recurse);
	
	showCanvas();

	runEvt('common', 'holdUpdated');
}


function holdProcessResult( hold, res, recurse ) {

	if( res && res > -1 ) {
		alert($('holds_success').innerHTML);
		holdArgs = null;
        if(isXUL() && typeof xulG.opac_hold_placed == 'function')
            xulG.opac_hold_placed(res);

	} else {

		if( recurse ) {
			alert($('holds_failure').innerHTML);
			return;
		}

		if( grep(res, function(e) { return (e.textcode == 'HOLD_EXISTS'); }) ) {
			if( fetchPermOrgs('HOLD_EXISTS.override')[0] != -1 ) {
				if( confirm($('hold_dup_exists_override').innerHTML) ) {
					return holdsPlaceHold(hold, true);
				}
                return;

			} else {
				return alert($('hold_dup_exists').innerHTML);
			}
		}

		if( grep(res, function(e) { return (e.textcode == 'HOLD_ITEM_CHECKED_OUT'); }) ) {
			if( fetchPermOrgs('HOLD_ITEM_CHECKED_OUT.override')[0] != -1 ) {
				if( confirm($('hold_checked_out_override').innerHTML) ) {
					return holdsPlaceHold(hold, true);
				}
                return;

			} else {
				return alert($('hold_checked_out').innerHTML);
			}
		}


		alert($('holds_failure').innerHTML);
	}
}


function holdsCancel(holdid, user) {
	if(!user) user = G.user;
	var req = new Request(CANCEL_HOLD, user.session, holdid, /* Patron via OPAC */ 6);
	req.send(true);
	return req.result();
	runEvt('common', 'holdUpdated');
}

function holdsUpdate(hold, user) {
	if(!user) user = G.user;
	var req = new Request(UPDATE_HOLD, user.session, hold);
	req.send(true);
	var x = req.result(); // cause an exception if there is one 
	runEvt('common', 'holdUpdated');
}

/* verify that the thaw date is valid and after today */
function holdsVerifyThawDate(dateString, isGreater) {
    thawDate = dojo.date.stamp.fromISOString(dateString);
    if(thawDate) {
        if(isGreater) {
            if(dojo.date.compare(thawDate) > 0) {
                return dojo.date.stamp.toISOString(thawDate);
            }
        } else {
            return dojo.date.stamp.toISOString(thawDate);
        }
    }
    return null;
}

function holdsVerifyThawDateUI(element) {
    value = dojo.date.stamp.toISOString(dijit.byId(element).getValue());

    if(!value) {
        removeCSSClass($(element), 'invalid_field');
        return;
    }

    if(!holdsVerifyThawDate(value, true)) {
        addCSSClass($(element), 'invalid_field');
    } else {
        removeCSSClass($(element), 'invalid_field');
    }
}

