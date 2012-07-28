function openClaimVoucherWindow() {
    var win = window.open(
        "", "", "resizable,width=800,height=600,scrollbars=1,chrome"
    );
    /* XXX i18n - also, the reason this isn't loaded from a server-side page
     * has to do with problems of knowing when the page has loaded, so we
     * can begin maniuplating it. we could retrieve content with an xhr call
     * though...
     */
    win.document.title = "Claim Voucher";
    win.document.body.innerHTML =
        '<h1>Claim Voucher</h1>' +
        '<div>' +
        '<button id="print" onclick="window.print();" disabled="disabled">' +
        'Loading...' +
        '</button>' +
        '</div>' +
        '<hr />' +
        '<div id="main"></div>'
    ;
    return win;
};
