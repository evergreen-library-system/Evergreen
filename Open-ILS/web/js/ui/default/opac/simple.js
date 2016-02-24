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

    $("adv_global_input_table").rows[$("adv_global_input_table").rows.length - 2].getElementsByTagName("input")[0].value = "";
}

(function($){
var _search_row_template, _expert_row_template, t;
var _el_adv_global_row = $("adv_global_row"), _el_adv_expert_row = $("adv_expert_row");
if (_el_adv_global_row) {
    t = _el_adv_global_row.cloneNode(true);
    t.id = null;
    _search_row_template = t;
}

if (_el_adv_expert_row) {
    t = _el_adv_expert_row.cloneNode(true);
    t.id = null;
    _expert_row_template = t;
}
function addExpertRow() {
    $("adv_expert_rows_here").appendChild(
        _expert_row_template.cloneNode(true)
    );
}

window.addSearchRow = addSearchRow;
window.addExpertRow = addExpertRow;
})($);
function killRowIfAtLeast(min, link) {
    var row = link.parentNode.parentNode;
    if (row.parentNode.getElementsByTagName("tr").length > min)
        row.parentNode.removeChild(row);
    return false;
}
function print_node(node_id) {
    var iframe = document.createElement("iframe");
    var source_node = $(node_id);
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

function search_modifier_onchange(type, checkbox, submitOnChange) {
    if (checkbox.form._adv && !checkbox.checked) {
        var search_box = $('search_box');
        var reg = new RegExp('#' + type + ' ?', 'g');
        search_box.value = search_box.value.replace(reg, "");
    }

    if (submitOnChange) {  
        checkbox.form.submit(); 
    }
}

function exclude_onchange(checkbox) {
    if (checkbox.form._adv && !checkbox.checked) {
        var search_box = $('search_box');
        // Other functions' form submits may create duplicates of this, so /g
        var reg = /-search_format\(electronic\)/g;
        search_box.value = search_box.value.replace(reg, "");
    }

    checkbox.form.submit();
}
