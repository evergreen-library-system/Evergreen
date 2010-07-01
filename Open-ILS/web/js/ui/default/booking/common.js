dojo.require("dijit.form.Button");

/* Quick and dirty way to localize some strings; not recommended for reuse.
 * I'm sure dojo provides a better mechanism for this, but at the moment
 * this is faster to implement anew than figuring out the Right way to do
 * the same thing w/ dojo.
 */
function init_auto_l10n(el) {
    function do_it(myel, cls) {
        if (cls) {
            var clss = cls.split(" ");
            for (var k in clss) {
                var parts = clss[k].match(/^AUTO_ATTR_([A-Z]+)_.+$/);
                if (parts && localeStrings[clss[k]]) {
                    myel.setAttribute(
                        parts[1].toLowerCase(), localeStrings[clss[k]]
                    );
                } else if (clss[k].match(/^AUTO_/) && localeStrings[clss[k]]) {
                    myel.innerHTML = localeStrings[clss[k]];
                }
            }
        }
    }

    for (var i in el.attributes) {
        if (el.attributes[i].nodeName == "class") {
            do_it(el, el.attributes[i].value);
            break;
        }
    }
    for (var i in el.childNodes) {
        if (el.childNodes[i].nodeType == 1) { // element node?
            init_auto_l10n(el.childNodes[i]); // recurse!
        }
    }
}

function get_keys(L) { var K = []; for (var k in L) K.push(k); return K; }
function hide_dom_element(e) { e.style.display = "none"; };
function reveal_dom_element(e) { e.style.display = ""; };
function formal_name(u) {
    var name = u.family_name() + ", " + u.first_given_name();
    if (u.second_given_name())
        name += (" " + u.second_given_name());
    return name;
}
function humanize_timestamp_string(ts) {
    /* For now, this discards time zones. */
    var parts = ts.split("T");
    var timeparts = parts[1].split("-")[0].split(":");
    return parts[0] + " " + timeparts[0] + ":" + timeparts[1];
}
function humanize_timestamp_string2(ts) {
    /* For now, this discards time zones, too. */
    var parts = ts.split(" ");
    parts[1] = parts[1].replace(/[\-\+]\d+$/, "");
    var timeparts = parts[1].split("-")[0].split(":");
    return parts[0] + " " + timeparts[0] + ":" + timeparts[1];
}
function is_ils_event(e) { return (e.ilsevent != undefined); }
function is_ils_actor_card_error(e) {
    return (e.textcode == "ACTOR_CARD_NOT_FOUND");
}
function my_ils_error(leader, e) {
    var s = leader + "\n";
    var keys = [
        "ilsevent", "desc", "textcode", "servertime", "pid", "stacktrace"
    ];
    for (var i in keys) {
        if (e[keys[i]]) s += ("\t" + keys[i] + ": " + e[keys[i]] + "\n");
    }
    return s;
}
function set_datagrid_empty_store(grid, flattener) {
    grid.setStore(
        new dojo.data.ItemFileReadStore(
            {"data": flattener([])}
        )
    );
}
