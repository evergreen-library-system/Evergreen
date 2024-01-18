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

    //Number of notification methods used
    var numNotifications = 0;

    //Array.from(alertMethodCboxes).forEach(function(cbox){
    for (var i = 0; i < alertMethodCboxes.length; i++){
        var cbox = alertMethodCboxes[i];
        if (cbox.checked && !cbox.disabled) {
            numNotifications = numNotifications + 1;
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

    //return { isValid: isFormOK, culpritNames : culprits };
    return { isValid: isFormOK, culpritNames : culprits, numNotifications : numNotifications };
}

function confirmMultipleHolds() {
    var result = true;
    var numSelect = document.getElementById("num_copies");
    if (numSelect) {
        var num = parseInt(numSelect.value);
        if (num > 1) {
            result = window.confirm(eg_opac_i18n.EG_MULTIHOLD_MESSAGE.format(num));
        }
    }
    return result;
}

function isValidDate(dateString){
    // First check for the pattern
    if(!/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(dateString))
        return false;

    // Parse the date parts to integers
    var parts = dateString.split("/");
    var day = parseInt(parts[1], 10);
    var month = parseInt(parts[0], 10);
    var year = parseInt(parts[2], 10);

    var today = new Date();

    if (today.getFullYear() > year){
      return false;
    }
    else if (today.getFullYear() == year ) {
      if(today.getMonth() +1 > month) {
         return false;
      }
      else if (today.getMonth() +1 == month) {
         if (today.getDate() > day) return false;
      }
   }

    // Check the ranges of month and year
    if(year < 2000 || year > 3000 || month == 0 || month > 12) return false;

    var monthLength = [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ];

    // Adjust for leap years
    if(year % 400 == 0 || (year % 100 != 0 && year % 4 == 0))  monthLength[1] = 29;

    // Check the range of the day
    return day > 0 && day <= monthLength[month - 1];
}

function validateHoldForm() {
    var res = validateMethodSelections(document.getElementsByClassName("hold-alert-method"));

    if (document.getElementById('hold_suspend').checked && document.getElementById('thaw_date').value.length > 0){
       //check that the date is not in the past
       if(!isValidDate(document.getElementById('thaw_date').value)) {
          alert(eg_opac_i18n.EG_INVALID_DATE);
          document.getElementById('thaw_date').style.backgroundColor  = "yellow";
          return false;
       }
    }


    if (res.isValid) {
        var result = confirmMultipleHolds();
        
        //Check for notification options
        if (res.numNotifications == 0) {
            var numNotificationsResponse = confirm("    No notification options are selected.    \n     Are you sure you want to continue?");
            if (numNotificationsResponse == false) {
                return false;
            }
        }
        if (result) {
            var submit_element = document.getElementById("place_hold_submit");
            submit_element.disabled = true;
        }
        return result;
    } else {
        alert(eg_opac_i18n.EG_MISSING_REQUIRED_INPUT);
        res.culpritNames.forEach(function(n){
            document.getElementsByName(n)[0].style.backgroundColor  = "yellow";
        });
        return false;
    }
}

