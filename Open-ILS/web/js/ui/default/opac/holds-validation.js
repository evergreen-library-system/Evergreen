/* JS form validation for holds page alert methods */
function resetBackgrounds(names){
    for (var key in names) {
        if (names.hasOwnProperty(key)) {
            var l = document.getElementsByName(names[key]);
            if (l.length > 0) {
                l[0].style.backgroundColor  = "";
            }
        }
    }
}

function validateMethodSelections (alertMethodCboxes) {
    var needsPhone = false;
    var hasPhone = false;
    
    var needsEmail = false;
    var hasEmail = false;
    
    var needsSms = false;
    var hasSms = false;
    var inputNames = { e: "email_address", ph: "phone_notify", sms: "sms_notify", carrier: "sms_carrier"};
    resetBackgrounds(inputNames);

    //Array.from(alertMethodCboxes).forEach(function(cbox){
    for (var i = 0; i < alertMethodCboxes.length; i++){
        var cbox = alertMethodCboxes[i];
        if (cbox.checked && !cbox.disabled) {
            switch(cbox.id){
                case "email_notify_checkbox":
                    needsEmail = true;
                    hasEmail = document.getElementsByName(inputNames.e)[0].innerHTML !== "";
                    break;
                case "phone_notify_checkbox":
                    needsPhone = true;
                    hasPhone = document.getElementsByName(inputNames.ph)[0].value !== "";
                    break;
                case "sms_notify_checkbox":
                    needsSms = true;
                    var smsNumInput = document.getElementsByName(inputNames.sms)[0];
                    hasSms = document.getElementsByName(inputNames.carrier)[0].value !== "" && smsNumInput.value !== ""; // todo: properly validate phone nums
                break;
            }
        }
    }
    
    var culprits = [];
    var emailOK = (needsEmail && hasEmail) || (!needsEmail);
    var phoneOK = needsPhone && hasPhone || (!needsPhone);
    var smsOK = needsSms && hasSms || (!needsSms);
    
    if (!phoneOK) {
        culprits.push("phone_notify");
    }
    if (!smsOK) {
        culprits.push("sms_notify", "sms_carrier");
    }
    
    var isFormOK = emailOK && phoneOK && smsOK;
    return { isValid: isFormOK, culpritNames : culprits };
}

function validateHoldForm() {
    var res = validateMethodSelections(document.getElementsByClassName("hold-alert-method"));
    if (res.isValid)
    {
        return true;
    } else {
        alert(eg_opac_i18n.EG_MISSING_REQUIRED_INPUT);
        res.culpritNames.forEach(function(n){
            document.getElementsByName(n)[0].style.backgroundColor  = "yellow";
        });
        return false;
    }
}

