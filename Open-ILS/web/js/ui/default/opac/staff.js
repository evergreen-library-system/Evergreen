/* staff client integration functions */
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
function no_hold_submit(event) {
    if (event.which == 13) {
        staff_hold_usr_barcode_changed();
        return false;
    }
    return true;
}
var cur_hold_barcode = undefined;
function staff_hold_usr_barcode_changed(isload) {
    if(typeof xulG != 'undefined' && xulG.get_barcode_and_settings) {
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
        if(barcode == undefined || barcode == '' || barcode == cur_hold_barcode)
            return;
        var load_info = xulG.get_barcode_and_settings(window, barcode, only_settings);
        if(load_info == false || load_info == undefined)
            return;
        cur_hold_barcode = load_info.barcode;
        if(!only_settings || (isload && isload !== true)) document.getElementById('hold_usr_input').value = load_info.barcode; // Safe at this point as we already set cur_hold_barcode
        if(load_info.settings['opac.default_pickup_location'])
            document.getElementById('pickup_lib').value = load_info.settings['opac.default_pickup_location'];
        if(!load_info.settings['opac.default_phone']) load_info.settings['opac.default_phone'] = '';
        if(!load_info.settings['opac.default_sms_notify']) load_info.settings['opac.default_sms_notify'] = '';
        if(!load_info.settings['opac.default_sms_carrier']) load_info.settings['opac.default_sms_carrier'] = '';
        if(load_info.settings['opac.hold_notify'] || load_info.settings['opac.hold_notify'] === '') {
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
        for(var i in update_elements) update_elements[i].value = load_info.settings['opac.default_phone'];
        update_elements = document.getElementsByName('sms_notify');
        for(var i in update_elements) update_elements[i].value = load_info.settings['opac.default_sms_notify'];
        update_elements = document.getElementsByName('sms_carrier');
        for(var i in update_elements) update_elements[i].value = load_info.settings['opac.default_sms_carrier'];
    }
}
window.onload = function() {
    // record details page events
    var rec = location.href.match(/\/opac\/record\/(\d+)/);
    if(rec && rec[1]) { 
        runEvt('rdetail', 'recordRetrieved', rec[1]); 
        runEvt('rdetail', 'MFHDDrawn');
    }
    if(location.href.match(/place_hold/)) {
        if(xulG.patron_barcode) {
            staff_hold_usr_barcode_changed(xulG.patron_barcode);
        } else {
            staff_hold_usr_barcode_changed(true);
        }
    }
}

function rdetail_next_prev_actions(index, count, prev, next, start, end, results) {
    /*  we mostly get the relative URL from the template:  recid?query_args...
        replace the recid and args on location.href to get the new URL  */
    function fullurl(url) {
        if (url.match(/eg\/opac\/results/)) {
            return location.href.replace(/eg\/opac\/.+$/, url);
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
        runEvt('rdetail', 'nextPrevDrawn', Number(index), Number(count)); 
    };
}
