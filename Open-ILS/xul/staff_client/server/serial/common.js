String.prototype.trim = function() {return this.replace(/^\s*(.+)\s*$/,"$1");}

/**
 * hard_empty() is needed because dojo.empty() doesn't seem to work on
 * XUL nodes. This also means that dojo.place() with a position argument of
 * "only" doesn't do what it should, but calling hard_empty() on the refnode
 * first will do the trick.
 */
function hard_empty(node) {
    if (typeof(node) == "string")
        node = dojo.byId(node);
    if (node)
        dojo.forEach(node.childNodes, dojo.destroy);
}

function hide(e) {
    if (typeof(e) == "string") e = dojo.byId(e);
    openils.Util.addCSSClass(e, "hideme");
}

function show(e) {
    if (typeof(e) == "string") e = dojo.byId(e);
    openils.Util.removeCSSClass(e, "hideme");
}

function hide_table_cell(e) {
    if (typeof(e) == "string") e = dojo.byId(e);

    e.style.display = "none";
    e.style.visibility = "hidden";
}

function show_table_cell(e) {
    if (typeof(e) == "string") e = dojo.byId(e);
    e.style.display = "table-cell";
    e.style.visibility = "visible";
}

function soft_hide(e) { /* doesn't disrupt XUL grid alignment */
    if (typeof(e) == "string") e = dojo.byId(e);
    e.style.visibility = "hidden";
}

function soft_show(e) {
    if (typeof(e) == "string") e = dojo.byId(e);
    e.style.visibility = "visible";
}

function busy(on) {
    if (typeof(busy._window) == "undefined")
        busy._window = dojo.query("window")[0];
    busy._window.style.cursor = on ? "wait" : "auto";
}

function T(s) { return document.createTextNode(s); }
function D(s) {return s ? openils.Util.timeStamp(s, {"selector":"date"}) : "";}
function node_by_name(s, ctx) {return dojo.query("[name='" + s + "']", ctx)[0];}

function num_sort(a, b) {
    [a, b] = [Number(a), Number(b)];
    return a > b ? 1 : (a < b ? -1 : 0);
}
