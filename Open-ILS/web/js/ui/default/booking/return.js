dojo.requireLocalization("openils.booking", "pickup_and_return");
var localeStrings = dojo.i18n.getLocalization(
    "openils.booking", "pickup_and_return"
);
var p;

function my_init() {
    p = new Populator({
        "out": out_bresv,
        "in": in_bresv,
        "patron": document.getElementById("patron_info")
    }, document.getElementById("barcode"));
    init_auto_l10n(document.getElementById("auto_l10n_start_here"));

    /* The following would handle pass-in from the patron interface, but
     * doesn't work (dirty solution, will come back to it, make it work,
     * clean it up). */
//    try {
//        document.getElementById("barcode").value =
//            xulG.bresv_interface_opts.patron_barcode;
//        document.getElementById("barcode_type").selectedIndex = 1;
//        document.getElementById("lookup").submit();
//    } catch (E) {
//        alert(E);
//    }
}
