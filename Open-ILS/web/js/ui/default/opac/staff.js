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
}
function staff_hold_usr_prepop() {
    if (xulG && xulG.patron_barcode) {
        var sel = document.getElementById("pickup_lib");
        for (var i = 0; i < sel.options.length; i++) {
            if (sel.options[i].value == xulG.patron_home_ou) {
                sel.selectedIndex = i;
                break;
            }
        }
        document.getElementById("hold_usr_input").value = xulG.patron_barcode;
        document.getElementById("hold_usr_input").disabled = false;
        document.getElementById("hold_usr_is_requestor_not").checked = true;

        var kill_this =
            document.getElementById("hold_usr_is_requestor").parentNode;
        kill_this.parentNode.removeChild(kill_this);
    }
}
window.onload = function() {
    // record details page events
    var rec = location.href.match(/\/opac\/record\/(\d+)/);
    if(rec && rec[1]) { runEvt('rdetail', 'recordRetrieved', rec[1]); }

    if (document.getElementById("hold_usr_input"))
        staff_hold_usr_prepop();

    // fire other events the staff client is expecting...
}
