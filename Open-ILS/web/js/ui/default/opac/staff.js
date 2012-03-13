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
window.onload = function() {
    // record details page events
    var rec = location.href.match(/\/opac\/record\/(\d+)/);
    if(rec && rec[1]) { 
        runEvt('rdetail', 'recordRetrieved', rec[1]); 
        runEvt('rdetail', 'MFHDDrawn');
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
