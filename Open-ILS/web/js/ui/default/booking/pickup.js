dojo.requireLocalization("openils.booking", "pickup_and_return");
var localeStrings = dojo.i18n.getLocalization(
    "openils.booking", "pickup_and_return"
);
var p;

function react_to_pass_in(opts) {
    if (opts && opts.patron_barcode) {
        p.populate({"patron": opts.patron_barcode});

        hide_dom_element(
            document.getElementById("contains_barcode_control")
        );
        document.getElementById("patron_barcode").value = opts.patron_barcode;
        p._extra_resetting = function() {
            reveal_dom_element(
                document.getElementById("contains_barcode_control")
            );
        };
    }
}

function my_init() {
    p = new Populator({
        "ready": ready_bresv,
        "out": out_bresv,
        "patron": document.getElementById("patron_info")
    }, document.getElementById("patron_barcode"));
    init_auto_l10n(document.getElementById("auto_l10n_start_here"));

    setTimeout(
        function() {
            var opts;
            if (typeof xulG != 'undefined' && typeof xulG.bresv_interface_opts != 'undefined') {
                opts = xulG.bresv_interface_opts;
            } else {
                opts = {};
            }
            var uri = location.href;
            var query = uri.substring(uri.indexOf("?") + 1, uri.length);
            var queryObject = dojo.queryToObject(query);
            if (typeof queryObject['patron_barcode'] != 'undefined') {
                opts.patron_barcode = queryObject['patron_barcode'];
            }
            react_to_pass_in(opts);
        }, 0
    );
}
