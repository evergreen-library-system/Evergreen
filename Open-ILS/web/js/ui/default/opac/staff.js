/* staff client integration functions */

// Browser staff client runs the TPAC within an iframe, whose onload
// is not called until after the page onload is called. window.onload
// actions are wrapped in timeouts (below) to ensure the wrapping page
// has a chance to insert the necessary xulG, etc. functions into the
// window.

function debug(msg){dump(msg+'\n')}
var eventCache={};
function attachEvt(scope, name, action) {
    if(!eventCache[scope]) eventCache[scope] = {};
    if(!eventCache[scope][name]) eventCache[scope][name] = [];
    eventCache[scope][name].push(action);
}
function runEvt(scope, name) {
    debug('running event '+scope+':'+name);
    var args = Array.prototype.slice.call(arguments).slice(2);
    if(eventCache[scope]) {
        var evt = eventCache[scope][name];
        for(var i in evt) {evt[i].apply(evt[i], args);}
    } 
}
function staff_hold_usr_input_disabler(input) {
    document.getElementById("hold_usr_input").disabled =
        Boolean(Number(input.value));
    staff_hold_usr_barcode_changed();
}
var debounce_barcode_change = function() {
    var timeout;

    return function(event) {
        clearTimeout(timeout);
        document.getElementById('patron_usr_barcode_not_found').style.display = 'none';

        if (event.which == '13') {
            staff_hold_usr_barcode_changed();
            return false;
        }

        var duration = event.type == 'paste' ? 0 : 500;
        timeout = setTimeout(staff_hold_usr_barcode_changed, duration);

        return true;
    };
}();
function staff_hold_usr_barcode_changed(isload) {

    if (!document.getElementById('place_hold_submit')) {
        // in some cases, the submit button is not present.
        // exit early to avoid needless JS errors
        return;
    }

    if (!window.xulG) return;
 
    var adv_link = document.getElementById('advanced_hold_link');
    if (adv_link) {
        adv_link.setAttribute('href', adv_link.getAttribute('href').replace(/&?is_requestor=[01]/,''));
        var is_requestor = document.getElementById('hold_usr_is_requestor').checked ? 1 : 0;
        adv_link.setAttribute('href', adv_link.getAttribute('href') + '&is_requestor=' + is_requestor.toString());
    }

    var cur_hold_barcode = undefined;
    var barcode = isload;
    if(!barcode || barcode === true) barcode = document.getElementById('staff_barcode').value;
    var only_settings = true;
    if(!document.getElementById('hold_usr_is_requestor').checked) {
        if(!isload) {
            barcode = document.getElementById('hold_usr_input').value;
            only_settings = false;
        }
        if(barcode && barcode != '' && !document.getElementById('hold_usr_is_requestor_not').checked)
            document.getElementById('hold_usr_is_requestor_not').checked = 'checked';
    }
    if(barcode == undefined || barcode == '') {
        document.getElementById('patron_name').innerHTML = '';
        // No submitting on empty barcode, but empty barcode doesn't really count as "not found" either
        document.getElementById('place_hold_submit').disabled = true;
        document.getElementById("patron_usr_barcode_not_found").style.display = 'none';
        cur_hold_barcode = null;
        return;
    }
    if(barcode == cur_hold_barcode)
        return;
    // No submitting until we think the barcode is valid
    document.getElementById('place_hold_submit').disabled = true;

    if (window.IAMBROWSER) {
        // Browser client operates asynchronously
        if (!xulG.get_barcode_and_settings_async) return;
        xulG.get_barcode_and_settings_async(barcode, only_settings)
        .then(
            function(load_info) { // load succeeded
                staff_hold_usr_barcode_changed2(
                    isload, only_settings, barcode, cur_hold_barcode, load_info);
            },
            function() { 
                // load failed (rejected).  Call staff_hold_usr_barcode_changed2
                // anyway, since it handles clearing the form
                staff_hold_usr_barcode_changed2(
                    isload, only_settings, barcode, cur_hold_barcode, false);
            }
        )
    } else {
        // XUL version is synchronous
        if (!xulG.get_barcode_and_settings) return;
        var load_info = xulG.get_barcode_and_settings(window, barcode, only_settings);
        staff_hold_usr_barcode_changed2(isload, only_settings, barcode, cur_hold_barcode, load_info);
    }
}

function staff_hold_usr_barcode_changed2(
    isload, only_settings, barcode, cur_hold_barcode, load_info) {

    if(load_info == false || load_info == undefined) {
        document.getElementById('patron_name').innerHTML = '';
        document.getElementById("patron_usr_barcode_not_found").style.display = '';
        cur_hold_barcode = null;
        return;
    }
    cur_hold_barcode = load_info.barcode;
    if (!only_settings || (isload && isload !== true)) {
        // Safe at this point as we already set cur_hold_barcode
        document.getElementById('hold_usr_input').value = load_info.barcode;

        // Patron preferred pickup loc always overrides the default pickup lib
        document.getElementById('pickup_lib').value = 
            load_info.settings['opac.default_pickup_location'] ?
            load_info.settings['opac.default_pickup_location'] : load_info.pickup_lib;
    }

    if (!load_info.settings['opac.default_sms_notify']){
        load_info.settings['opac.default_sms_notify'] = '';
    }

    if (!load_info.settings['opac.default_sms_carrier']){
        load_info.settings['opac.default_sms_carrier'] = '';
    }

    if (load_info.settings['opac.hold_notify'] || load_info.settings['opac.hold_notify'] === '') {
        var email = load_info.settings['opac.hold_notify'].indexOf('email') > -1;
        var phone = load_info.settings['opac.hold_notify'].indexOf('phone') > -1;
        var sms = load_info.settings['opac.hold_notify'].indexOf('sms') > -1;
        var update_elements = document.getElementsByName('email_notify');
        for(var i in update_elements) update_elements[i].checked = (email ? 'checked' : '');
        update_elements = document.getElementsByName('phone_notify_checkbox');
        for(var i in update_elements) update_elements[i].checked = (phone ? 'checked' : '');
        update_elements = document.getElementsByName('sms_notify_checkbox');
        for(var i in update_elements) update_elements[i].checked = (sms ? 'checked' : '');
    }

    update_elements = document.getElementsByName('phone_notify');
    for(var i in update_elements) update_elements[i].value = load_info.settings['opac.default_phone']
        ? load_info.settings['opac.default_phone'] : '';
    update_elements = document.getElementsByName('sms_notify');
    for(var i in update_elements) update_elements[i].value = load_info.settings['opac.default_sms_notify'];
    update_elements = document.getElementsByName('sms_carrier');
    for(var i in update_elements) update_elements[i].value = load_info.settings['opac.default_sms_carrier'];
    update_elements = document.getElementsByName('email_notify');
    for(var i in update_elements) {
        update_elements[i].disabled = (load_info.user_email ? false : true);
        if(update_elements[i].disabled) update_elements[i].checked = false;
    }
    update_elements = document.getElementsByName('email_address');
    for(var i in update_elements) update_elements[i].textContent = load_info.user_email;
    if(!document.getElementById('hold_usr_is_requestor').checked && document.getElementById('hold_usr_input').value) {
        document.getElementById('patron_name').innerHTML = load_info.patron_name;
        document.getElementById("patron_usr_barcode_not_found").style.display = 'none';
    }
    // Ok, now we can allow submitting again, unless this is a "true" load, in which case we likely have a blank barcode box active

    // update the advanced hold options link to propagate the patron
    // barcode if clicked.  This is needed when the patron barcode
    // is manually entered (i.e. the staff client does not provide one).
    var adv_link = document.getElementById('advanced_hold_link');
    if (adv_link) { // not present on MR hold pages
        var href = adv_link.getAttribute('href').replace(
            /;usr_barcode=[^;\&]+|$/, 
            ';usr_barcode=' + encodeURIComponent(cur_hold_barcode));
        adv_link.setAttribute('href', href);
    }

    if (isload !== true)
        document.getElementById('place_hold_submit').disabled = false;
}
window.onload = function() {
    // record details page events

    setTimeout(function() {

        if (location.href.match(/is_requestor=[01]/)) {
            var loc = location.href;
            var is_req_match = new RegExp("is_requestor=[01]");
            var is_req = is_req_match.exec(loc).toString();
            is_req = is_req.replace(/is_requestor=/, '');
            if (is_req == "1") {
                document.getElementById('hold_usr_is_requestor').checked = 'checked';
                document.getElementById('hold_usr_input').disabled = true;
            } else {
                document.getElementById('hold_usr_is_requestor_not').checked = 'checked';
                document.getElementById('hold_usr_input').disabled = false;
            }
        }

        var rec = location.href.match(/\/opac\/record\/(\d+)/);
        if(rec && rec[1]) { 
            runEvt('rdetail', 'recordRetrieved', rec[1]); 
            runEvt('rdetail', 'MFHDDrawn');
        }
        if(location.href.match(/place_hold/)) {
            // patron barcode may come from XUL or a CGI param
            var patron_barcode = xulG.patron_barcode ||
                document.getElementById('hold_usr_input').value;
            if(patron_barcode) {
                staff_hold_usr_barcode_changed(patron_barcode);
            } else {
                staff_hold_usr_barcode_changed(true);
            }
        }
    });
}

function rdetail_next_prev_actions(index, count, prev, next, start, end, results) {
    /*  we mostly get the relative URL from the template:  recid?query_args...
        replace the recid and args on location.href to get the new URL  */
    function fullurl(url) {
        if (url.match(/eg\/opac\/results/)) {
            return location.href.replace(/\/eg\/opac\/.+$/, url);
        } else {
            return location.href.replace(/\/\d+\??.*/, '/' + url);
        }
    }

    if (index > 0) {
        if(prev) 
            window.rdetailPrev = function() { location.href = fullurl(prev); }
        if(start) 
            window.rdetailStart = function() { location.href = fullurl(start); }
    }

    if (index < count - 1) {
        if(next) 
            window.rdetailNext = function() { location.href = fullurl(next); }
        if(end) 
            window.rdetailEnd = function() { location.href = fullurl(end); }
    }

    window.rdetailBackToResults = function() { location.href = fullurl(results); };

    ol = window.onload;
    window.onload = function() {
        if(ol) ol(); 
        setTimeout(function() {
            runEvt('rdetail', 'nextPrevDrawn', Number(index), Number(count)); 
        });
    };
}
