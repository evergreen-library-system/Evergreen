dojo.require('dojo.parser');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.TextBox');

dojo.requireLocalization("openils.opac", "opac");
opac_strings = dojo.i18n.getLocalization("openils.opac", "opac");

dojo.addOnLoad(function() {

    // Create the password reset dialog
    var pwResetFormDlg = createResetDialog();
    dojo.parser.parse();

    // Connect the buttons to submit / cancel events that override
    // the default actions associated with the buttons to do
    // pleasing Ajax things
    dojo.connect(dijit.byId("pwCancel"), "onClick", function(event) {
        event.preventDefault();
        event.stopPropagation();
        pwResetFormDlg.hide();
        dijit.byId('pwUsername').attr('value', null);
        dijit.byId('pwBarcode').attr('value', null);
    });
    dojo.connect(dijit.byId("pwSubmit"), "onClick", function(event) {
        event.preventDefault();
        event.stopPropagation();
        var xhrArgs = {
            form: dojo.byId("requestReset"),
            handleAs: "text",
            load: function(data) {
                pwResetFormDlg.hide();
                passwordSubmission(opac_strings.PWD_RESET_SUBMIT_SUCCESS);
                dijit.byId('pwUsername').attr('value', null);
                dijit.byId('pwBarcode').attr('value', null);
            },
            error: function(error) {
                pwResetFormDlg.hide();
                passwordSubmission(opac_strings.PWD_RESET_SUBMIT_ERROR);
            }
        }
        var deferred = dojo.xhrPost(xhrArgs);
    });
    dojo.place("<tr><td colspan='2' align='center'><a class='classic_link' id='pwResetLink' onClick='dijit.byId(\"pwResetFormDlg\").show();'</a></td></tr>", config.ids.login.tbody);
    dojo.query("#pwResetLink").attr("innerHTML", opac_strings.PWD_RESET_FORGOT_PROMPT);

});

function passwordSubmission( msg ) {
    var responseDialog = new dijit.Dialog({
        title: opac_strings.PWD_RESET_RESPONSE_TITLE,
        style: "width: 35em"
    });
    responseDialog.startup();
    var requestStatusDiv = dojo.create("div", { style: "width: 30em" });
    var requestStatusMsg = dojo.create("div", { innerHTML: msg }, requestStatusDiv);
    var okButton = new dijit.form.Button({
        id: "okButton",
        type: "submit",
        label: opac_strings.OK
    }).placeAt(requestStatusDiv);
    responseDialog.attr("content", requestStatusDiv);
    responseDialog.show();
    dojo.connect(dijit.byId("okButton"), "onClick", responseDialog, "hide");
}

function createResetDialog() {
    var pwResetFormDlg = new dijit.Dialog({
        id: "pwResetFormDlg",
        title: opac_strings.PWD_RESET_FORM_TITLE,
        style: "width: 35em"
    });
    pwResetFormDlg.startup();

    // Instantiate the form
    var pwResetFormURL = "/opac/password/" + (OpenSRF.locale || "en-US") + "/";
    var pwResetFormDiv = dojo.create("form", { id: "requestReset", style: "width: 30em", method: "post", action: pwResetFormURL });
    dojo.create("p", { innerHTML: opac_strings.PWD_RESET_SUBMIT_PROMPT }, pwResetFormDiv);
    var pwResetFormTable = dojo.create("table", null, pwResetFormDiv);
    var pwResetFormTbody = dojo.create("tbody", null, pwResetFormTable);
    var pwResetFormRow = dojo.create("tr", null, pwResetFormTbody);
    var pwResetFormCell = dojo.create("td", null, pwResetFormRow);
    var pwResetFormLabel = dojo.create("label", null, pwResetFormCell);
    dojo.attr(pwResetFormCell, { innerHTML: opac_strings.BARCODE_PROMPT });
    pwResetFormCell = dojo.create("td", null, pwResetFormRow);
    var barcodeText = new dijit.form.TextBox({
        id: "pwBarcode",
        name: "barcode"
    }).placeAt(pwResetFormCell);
    pwResetFormRow = dojo.create("tr", {}, pwResetFormTbody);
    pwResetFormCell = dojo.create("td", {}, pwResetFormRow);
    dojo.attr(pwResetFormCell, { innerHTML: opac_strings.USERNAME_PROMPT });
    pwResetFormCell = dojo.create("td", {}, pwResetFormRow);
    var usernameText = new dijit.form.TextBox({
        id: "pwUsername",
        name: "username"
    }).placeAt(pwResetFormCell);
    dojo.create("br", null, pwResetFormDiv);
    var submitButton = new dijit.form.Button({
        id: "pwSubmit",
        type: "submit",
        label: opac_strings.SUBMIT_BUTTON_LABEL
    }).placeAt(pwResetFormDiv);
    var cancelButton = new dijit.form.Button({
        id: "pwCancel",
        type: "cancel",
        label: opac_strings.CANCEL_BUTTON_LABEL
    }).placeAt(pwResetFormDiv);

    // Set the content of the Dialog to the pwResetForm
    pwResetFormDlg.attr("content", pwResetFormDiv);
    return pwResetFormDlg;
}

