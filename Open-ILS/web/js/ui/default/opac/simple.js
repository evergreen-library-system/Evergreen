/* Keep this dead simple. No dojo. */
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
function print_node(node_id) {
    var iframe = document.createElement("iframe");
    var source_node = document.getElementById(node_id);
    source_node.parentNode.appendChild(iframe);

    var iwin = iframe.contentWindow;

    /* These next three statements are only needed by IE, but they don't
     * hurt FF/Chrome. */
    iwin.document.open();
    iwin.document.write(    /* XXX make better/customizable? */
        "<html><head><title>Recipt</title></head><body></body></html>"
    );
    iwin.document.close();

    iwin.document.body.innerHTML = source_node.innerHTML;
    iframe.focus();

    try { iframe.print(); } catch (e) { iwin.print(); }
    setTimeout(function() { iframe.style.display = "none"; }, 3500);
}
