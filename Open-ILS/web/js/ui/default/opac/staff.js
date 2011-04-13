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
window.onload = function() {
    // record details page events
    var rec = location.href.match(/\/opac\/record\/(\d+)/);
    if(rec && rec[1]) { runEvt('rdetail', 'recordRetrieved', rec[1]); }
    // fire other events the staff client is expecting...
}
