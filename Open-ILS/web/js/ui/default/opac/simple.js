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

var _search_row_template, _expert_row_template;
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
function addExpertRow() {
    if (!_expert_row_template) {
        t = $("adv_expert_row").cloneNode(true);
        t.id = null;
        _expert_row_template = t;
    }

    $("adv_expert_rows_here").appendChild(
        _expert_row_template.cloneNode(true)
    );
}
function killRowIfAtLeast(min, link) {
    var row = link.parentNode.parentNode;
    if (row.parentNode.getElementsByTagName("tr").length > min)
        row.parentNode.removeChild(row);
    return false;
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
        "<html><head><title>Receipt</title></head><body></body></html>"
    );
    iwin.document.close();

    iwin.document.body.innerHTML = source_node.innerHTML;
    iframe.focus();

    try { iframe.print(); } catch (e) { iwin.print(); }
    setTimeout(function() { iframe.style.display = "none"; }, 3500);
}
function select_all_checkboxes(name, checked) {
    var all = document.getElementsByTagName("input");
    for (var i = 0; i < all.length; i++) {
        if (all[i].type == "checkbox" && all[i].name == name) {
            all[i].checked = checked;
        }
    }
}
function avail_change_adv_search(checkbox) {
    if (checkbox.form._adv && !checkbox.checked) {
        var search_box = document.getElementById("search_box");
        search_box.value = search_box.value.replace(/#available ?/g, "");
    }
}
