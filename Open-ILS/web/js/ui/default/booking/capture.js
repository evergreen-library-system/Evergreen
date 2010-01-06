dojo.require("openils.User");
dojo.require("openils.widget.OrgUnitFilteringSelect");
dojo.requireLocalization("openils.booking", "capture");

const CAPTURE_FAILURE = 0;
const CAPTURE_SUCCESS = 1;
const CAPTURE_UNKNOWN = 2;

var localeStrings = dojo.i18n.getLocalization("openils.booking", "capture");

function CaptureDisplay(element) { this.element = element; }
CaptureDisplay.prototype.no_payload = function() {
    this.element.appendChild(document.createTextNode(localeStrings.NO_PAYLOAD));
};
CaptureDisplay.prototype.dump = function(payload) {
    var div = document.createElement("div");
    div.appendChild(document.createTextNode(localeStrings.HERES_WHAT_WE_KNOW));
    this.element.appendChild(div);

    var ul = document.createElement("ul");
    for (var k in payload) {
        var li = document.createElement("li");
        li.appendChild(document.createTextNode(k + ": " + payload[k]));
        ul.appendChild(li);
    }
    this.element.appendChild(ul);
};
CaptureDisplay.prototype.generate_transit_display = function(payload) {
    var super_div = document.createElement("div");
    var div;

    div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.CAPTURE_CAUSES_TRANSIT
    ));
    div.setAttribute("class", "transit_notice");
    super_div.appendChild(div);

    div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.CAPTURE_TRANSIT_SOURCE + " " +
        fieldmapper.aou.findOrgUnit(payload.transit.source()).shortname()
    ));
    super_div.appendChild(div);

    div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.CAPTURE_TRANSIT_DEST + " " +
        fieldmapper.aou.findOrgUnit(payload.transit.dest()).shortname()
    ));
    super_div.appendChild(div);

    return super_div;
};
CaptureDisplay.prototype.display_with_transit_info = function(payload) {
    var div;

    div = document.createElement("div");
    div.appendChild(document.createTextNode(localeStrings.CAPTURE_INFO));
    div.setAttribute("class", "capture_info");
    this.element.appendChild(div);

    if (payload.catalog_item) {
        div = document.createElement("div");
        div.appendChild(document.createTextNode(
            localeStrings.CAPTURE_BRESV_BRSRC + " " +
            payload.catalog_item.barcode()
        ));
        this.element.appendChild(div);
    }

    div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.CAPTURE_BRESV_DATES + " " +
        humanize_timestamp_string(payload.reservation.start_time()) + " - " +
        humanize_timestamp_string(payload.reservation.end_time())
    ));
    this.element.appendChild(div);

    div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.CAPTURE_BRESV_PICKUP_LIB + " " +
        fieldmapper.aou.findOrgUnit(
            payload.reservation.pickup_lib()
        ).shortname()
    ));
    this.element.appendChild(div);

    div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.CAPTURE_BRESV_PATRON_BARCODE + " " +
        payload.reservation.usr().card().barcode()
    ));
    this.element.appendChild(div);

    if (payload.transit) {
        this.element.appendChild(this.generate_transit_display(payload));
    }
};
CaptureDisplay.prototype.clear = function() { this.element.innerHTML = ""; };
CaptureDisplay.prototype.load = function(payload) {
    try {
        this.element.appendChild(document.createElement("hr"));
        if (!payload) {
            this.no_payload();
        } else if (!payload.fail_cause && payload.captured) {
            this.display_with_transit_info(payload);
        } else {
            this.dump(payload);
        }
    } catch (E) {
        alert(E); /* XXX */
    }
};

var capture_display;
var last_result;

function clear_for_next() {
    if (last_result == CAPTURE_SUCCESS) {
        last_result = undefined;
        document.getElementById("result_display").innerHTML = "";
        document.getElementById("resource_barcode").value = "";
    }
}

function capture() {
    var barcode = document.getElementById("resource_barcode").value;
    var result = fieldmapper.standardRequest(
        [
            "open-ils.booking",
            "open-ils.booking.resources.capture_for_reservation"
        ],
        [xulG.auth.session.key, barcode]
    );

    if (result && result.ilsevent !== undefined) {
        if (result.payload && result.payload.captured > 0) {
            capture_display.load(result.payload);
            return CAPTURE_SUCCESS;
        } else {
            capture_display.load(result.payload);
            alert(my_ils_error(localeStrings.CAPTURED_NOTHING, result));
            return CAPTURE_FAILURE;
        }
    } else {
        return CAPTURE_UNKNOWN;
    }
}

function attempt_capture() {
    var rd = document.getElementById("result_display");
    capture_display.clear();
    switch(last_result = capture()) {
        case CAPTURE_FAILURE:
            rd.setAttribute("class", "capture_failure");
            rd.innerHTML = localeStrings.FAILURE;
            break;
        case CAPTURE_SUCCESS:
            rd.setAttribute("class", "capture_success");
            rd.innerHTML = localeStrings.SUCCESS;
            break;
        default:
            alert(localeStrings.UNKNOWN_PROBLEM);
            break;
    }
}

function my_init() {
    init_auto_l10n(document.getElementById("auto_l10n_start_here"));
    capture_display = new CaptureDisplay(
        document.getElementById("capture_display")
    );
}
