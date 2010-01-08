dojo.requireLocalization("openils.booking", "pickup_and_return");
var localeStrings = dojo.i18n.getLocalization(
    "openils.booking", "pickup_and_return"
);
var p;

function my_init() {
    p = new Populator({
        "ready": ready_bresv,
        "out": out_bresv,
        "patron": document.getElementById("patron_info")
    }, document.getElementById("patron_barcode"));
    init_auto_l10n(document.getElementById("auto_l10n_start_here"));

    /* The following would be for pass-in from the patron interface, but
     * doesn't yet work/is cheap and needs improved anyway. */
//    try {
//        document.getElementById("patron_barcode").value =
//            xulG.bresv_interface_opts.patron_barcode;
//        document.getElementById("lookup").submit();
//    } catch (E) {
//        ;
//    }
}
