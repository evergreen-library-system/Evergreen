/* Keep this dead simple. No dojo. Call nothing via onload. */
function $(s) { return document.getElementById(s); }
function removeClass(node, cls) {
    if (!node || !node.className) return;
    node.className =
        node.className.replace(new RegExp("\\b" + cls + "\\b", "g"), "");
}
function addClass(node, cls) {
    if (!node) return;
    removeClass(node, cls);
    if (!node.className) node.className = cls;
    else node.className += ' ' + cls;
}
function unHideMe(node) { removeClass(node, "hide_me"); }
function hideMe(node) { addClass(node, "hide_me"); }

var _search_row_template;
function addSearchRow() {
    if (!_search_row_template) {
        t = $("adv_global_row").cloneNode(true);
        t.id = null;
        _search_row_template = t;
    }

    $("adv_global_tbody").insertBefore(
        _search_row_template.cloneNode(true),
        $("adv_global_addrow")
    );
}
