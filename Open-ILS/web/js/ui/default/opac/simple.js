/* Keep this dead simple. No dojo. */

function get(s) { return document.getElementById(s); }
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
    const tBody = document.getElementById('adv_global_tbody');
    if (!_search_row_template) {
        t = tBody.getElementsByTagName("fieldset")[0].cloneNode(true);
        t.id = '';
        _search_row_template = t;
    }

    var insertPoint = document.getElementById('adv_global_addrow');
    var newFieldset = tBody.insertBefore(_search_row_template.cloneNode(true), insertPoint);

    // clear inputs
    newFieldset.querySelectorAll('input').forEach(input => {
        input.value = '';
    });
    
    reindexLegends(tBody);

    displayAlert('aria-search-row-added');

    // focus on first input in new fieldset
    newFieldset.querySelector('input').focus();
}

function addExpertRow() {
    // Needs to use class instead of id so you can delete the first row
    const clone = document.getElementsByClassName('adv_expert_row')[0].cloneNode(true);
    clone.id = '';
    // Clear input values in the new row
    clone.getElementsByTagName("input").forEach(input => {
        input.value = '';
    });
    const parent = document.getElementById("adv_expert_rows_here");
    parent.appendChild(clone);
    displayAlert('aria-search-row-added');
    reindexLegends(parent);
}

function killRowIfAtLeast(min, $event) {
    const link = $event.target;
    let row = link.closest("fieldset");
    let parent = row.parentNode;
    if (parent.getElementsByTagName("fieldset").length > min) {
        parent.removeChild(row);
        displayAlert('aria-search-row-removed');
        // re-number the legends 
        reindexLegends(parent);
        // focus on first input in last row
        parent.querySelector('input').focus();
    }
}

function removeSearchRows(event) {
    const tBody = document.getElementById('adv_global_tbody');
    tBody.removeChild(event.target.closest('fieldset'));
    displayAlert('aria-search-row-removed');
    // re-number the legends 
    reindexLegends(tBody);
    // focus on first input in last fieldset
    const fieldsets = tBody.getElementsByTagName('fieldset');
    const inputs = fieldsets[fieldsets.length - 1].getElementsByTagName('input');
    inputs[0].focus();
};

function reindexLegends(parent) {
    const fieldsets = parent.querySelectorAll('fieldset');
    if (!fieldsets) return;
    const digits = new RegExp(/[0-9]+/g);
    fieldsets.forEach(fs => {
        let n = Array.prototype.indexOf.call(fs.parentNode.querySelectorAll('fieldset'), fs) + 1;
        //console.debug('Reindexing fieldset ', n);
        fs.querySelector('legend').textContent = fs.querySelector('legend').textContent.replace(digits, n);
        let btn = fs.querySelector('.row-remover');
        let icon = btn.querySelector('i');
        let vh = btn.querySelector('.visually-hidden');
        icon.setAttribute('title', icon?.getAttribute('title').replace(digits, n));
        vh.textContent = vh?.textContent.replace(digits, n);
    } );
}

function print_node(node_id) {
    var iframe = document.createElement("iframe");
    var source_node = get(node_id);
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
        var search_box = get('search_box');
        var reg = new RegExp('#' + type + ' ?', 'g');
        search_box.value = search_box.value.replace(reg, "");
    }

    // Still alter the CGI params when the box is unchecked using a hidden input (to turn off highlighting too)
    if (type == "show_highlight" && checkbox.checked)
        document.getElementById("show_highlight_hidden").disabled = true;

    if (submitOnChange) {  
        checkbox.form.submit(); 
    }
}

function exclude_onchange(checkbox) {
    if (checkbox.form._adv && !checkbox.checked) {
        var search_box = get('search_box');
        // Other functions' form submits may create duplicates of this, so /g
        var reg = /-search_format\(electronic\)/g;
        search_box.value = search_box.value.replace(reg, "");
        // Remove from the search form itself
        var search_format_inputs = document.querySelectorAll('input[type="hidden"][name="fi:-search_format"][value="electronic"]');
        for (var j = 0; j < search_format_inputs.length; j++) {
            search_format_inputs[j].parentNode.removeChild(search_format_inputs[j]);
        }

    }

    checkbox.form.submit();
}

// prefs notify update holds-related code
var hold_notify_prefs = [];
document.addEventListener("DOMContentLoaded", function() {
    var form = document.getElementById('hold_notify_form');
    if (!form) return;
    var els = form.elements;
    for (i = 0; i < els.length; i++){
        var e = els[i];
        if (e.id.startsWith("opac") || e.id == 'sms_carrier'){
            hold_notify_prefs.push({
                name : e.id,
                oldval : e.type == 'checkbox' ? e.checked : e.value,
                newval : null
            });
            // set required attribute input fields that need it
            if (e.id.includes('hold_notify') && !e.id.includes('email')){
                var fieldToReq = e.id.includes('sms') ? 'opac.default_sms_notify' : 'opac.default_phone';
                toggle_related_required(fieldToReq, e.checked);
            }

        }
    }
    form.addEventListener('submit', addHoldUpdates);
});

function appendChgInputs(chg){
    // server-side we'll parse the param as an array where:
    // [ #oldval, #newval, #name, [#arr of affected holds], #propagateBool ]
    // this first POST will set the first three, and the confirmation interstitial
    // the rest.
    var form = document.getElementById('hold_notify_form');

    var inputold = document.createElement('input');
    inputold.setAttribute('type', 'hidden');
    inputold.setAttribute('name', chg.name + '[]');
    inputold.setAttribute('value', chg.oldval);
    form.appendChild(inputold);

    var inputnew = document.createElement('input');
    inputnew.setAttribute('type', 'hidden');
    inputnew.setAttribute('name', chg.name + '[]');
    inputnew.setAttribute('value', chg.newval);
    form.appendChild(inputnew);

    var inputname = document.createElement('input');
    inputname.setAttribute('type', 'hidden');
    inputname.setAttribute('name', chg.name + '[]');
    inputname.setAttribute('value', chg.name);
    form.appendChild(inputname);
}

function addHoldUpdates(){
    paramTranslate(hold_notify_prefs).forEach(function(chg){
        // only append a change if it actually changed from
        // what we had server-side originally
        if (chg.newval != null && chg.oldval != chg.newval) appendChgInputs(chg);
    });
    return true;
}

function chkPh(number){
    // normalize phone # for comparison, only digits
    if (number == null || number == undefined) return '';
    var regex = /[^\d]/g;
    return number.replace(regex, '');
}

function idxOfName(n){
    return hold_notify_prefs.findIndex(function(e){ return e.name === n});
}

function record_change(evt){
    var field = evt.target;
    switch(field.id){
        case "opac.hold_notify.email":
            var chg = hold_notify_prefs[idxOfName(field.id)]
            chg.newval = field.checked;
            break;
        case "opac.hold_notify.phone":
            var chg = hold_notify_prefs[idxOfName(field.id)]
            chg.newval = field.checked;
            toggle_related_required('opac.default_phone', chg.newval);
            break;
        case "opac.hold_notify.sms":
            var chg = hold_notify_prefs[idxOfName(field.id)]
            chg.newval = field.checked;
            toggle_related_required('opac.default_sms_notify', chg.newval);
            break;
        case "sms_carrier": // carrier id string
            var chg = hold_notify_prefs[idxOfName(field.id)]
            chg.newval = field.value;
            break;
        case "opac.default_phone":
            var chg = hold_notify_prefs[idxOfName(field.id)]
            if (chkPh(field.value) != chkPh(chg.oldval)){
                chg.newval = field.value;
            }
            break;
        case "opac.default_sms_notify":
            var chg = hold_notify_prefs[idxOfName(field.id)]
            if (chkPh(field.value) != chkPh(chg.oldval)){
                chg.newval = field.value;
                toggle_related_required('sms_carrier', chg.newval ? true : false);
            }
            break;
    }
}

// there are the param values for the changed fields we expect server-side
function paramTranslate(chArr){
    return chArr.map(function(ch){
        var n = "";
        switch(ch.name){
            case "opac.hold_notify.email":
                n = "email_notify";
                break;
            case "opac.hold_notify.phone":
                n = "phone_notify";
                break;
            case "opac.hold_notify.sms":
                n = "sms_notify";
                break;
            case "sms_carrier": // carrier id string
                n = "default_sms_carrier_id";
                break;
            case "opac.default_phone":
                n = "default_phone";
                break;
            case "opac.default_sms_notify":
                n = "default_sms";
                break;
        }
        return { name : n, oldval : ch.oldval, newval : ch.newval };
    });
}

function updateHoldsCheck() {
    // just dynamically add an input that flags that we have
    // holds-related updates
    var form = document.getElementById('hold_updates_form');
    if (!form) return;
    var els = form.elements;
    var isValid = false;
    for (i = 0; i < els.length; i++){
        var e = els[i];
        if (e.type == "checkbox" && e.checked){
            var flag = document.createElement('input');
            flag.setAttribute('name', 'hasHoldsChanges');
            flag.setAttribute('type', 'hidden');
            flag.setAttribute('value', 1);
            form.appendChild(flag);
            isValid = true;
            return isValid;
        }
    }
    alert("No option selected.");
    return isValid;
}

function check_sms_carrier(e){
    var sms_num = e.target;
    // if sms number has anything in it that's not just whitespace, then require a carrier
    if (!sms_num.value.match(/\S+/)) return;

    var carrierSelect = document.getElementById('sms_carrier');
    if (carrierSelect.selectedIndex == 0){
        carrierSelect.setAttribute("required", "");
    }

}

function canSubmit(evt){
   // check hold updates form to see if we have any selected
   // enable the submit button if we do
    var form = document.getElementById('hold_updates_form');
    var submit = form.querySelector('input[type="submit"]');
    if (!form || !submit) return;
    var els = form.elements;
    for (i = 0; i < els.length; i++){
        var e = els[i];
        if (e.type == "checkbox" && !e.hidden && e.checked){
            submit.removeAttribute("disabled");
            return;
        }
    }

    submit.setAttribute("disabled","");
}

function toggle_related_required(id, isRequired){
    var input = document.getElementById(id);
    input.required = isRequired;
}

function displayAlert(elementID) {
    const el = document.getElementById(elementID);
    // clear previous alerts
    el.parentElement.querySelectorAll('.alert').forEach(alert => {alert.classList.add('d-none')});
    // display the chosen alert
    el.classList.remove('d-none');
    // fade out after 8 seconds
    setTimeout(() => {document.getElementById(elementID).classList.add('d-none')}, 8000);
}

function canSubmitPayment(evt){
   // check that charges are selected in opac for payment
   // enable the submit payment button if they are
    var form = document.getElementById('selected_fines');
    var submit = form.querySelector('input[type="submit"]');
    if (!form || !submit) return;
    var els = form.elements;
    for (i = 0; i < els.length; i++){
        var e = els[i];
        if (e.type == "checkbox" && !e.hidden && e.checked){
            submit.removeAttribute("disabled");
            return;
        }
    }

    submit.setAttribute("disabled","");
}
