dojo.require("openils.User");
dojo.require("openils.widget.OrgUnitFilteringSelect");
dojo.requireLocalization("openils.booking", "capture");

const CAPTURE_FAILURE = 0;
const CAPTURE_SUCCESS = 1;
const CAPTURE_UNKNOWN = 2;

var localeStrings = dojo.i18n.getLocalization("openils.booking", "capture");

function CaptureDisplay(control_holder, data_holder) {
    this.control_holder = control_holder;
    this.data_holder = data_holder;
}
CaptureDisplay.prototype.no_payload = function() {
    this.data_holder.appendChild(
        document.createTextNode(localeStrings.NO_PAYLOAD)
    );
};
CaptureDisplay.prototype.dump = function(payload) {
    var div = document.createElement("div");
    div.appendChild(document.createTextNode(localeStrings.HERES_WHAT_WE_KNOW));
    this.data_holder.appendChild(div);

    var ul = document.createElement("ul");
    for (var k in payload) {
        var li = document.createElement("li");
        li.appendChild(document.createTextNode(k + ": " + payload[k]));
        ul.appendChild(li);
    }
    this.data_holder.appendChild(ul);
};
CaptureDisplay.prototype._generate_barcode_line = function(payload) {
    var div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.BARCODE + ": " + payload.resource.barcode()
    ));
    return div;
};
CaptureDisplay.prototype._generate_title_line = function(payload) {
    var div = document.createElement("div");
    div.appendChild(document.createTextNode(
        localeStrings.TITLE + ": " +
        (payload.mvr ? payload.mvr.title() : payload.type.name())
    ));
    return div;
};
CaptureDisplay.prototype._generate_author_line = function(payload) {
    var div = document.createElement("div");
    if (payload.mvr) {
        div.appendChild(document.createTextNode(
            localeStrings.AUTHOR + ": " + payload.mvr.author()
        ));
    }
    return div;
};
CaptureDisplay.prototype._generate_transit_notice = function(payload) {
    var div = document.createElement("div");
    if (payload.transit) {
        div.setAttribute("class", "transit_notice");
        div.appendChild(document.createTextNode(localeStrings.TRANSIT));
    }
    return div;
};
CaptureDisplay.prototype._generate_route_line = function(payload) {
    var div = document.createElement("div");
    var strong = document.createElement("strong");
    strong.appendChild(document.createTextNode(
        (payload.transit ?
            fieldmapper.aou.findOrgUnit(payload.transit.dest()).shortname() :
            localeStrings.RESERVATION_SHELF) + ":"
    ));
    div.appendChild(document.createTextNode(
        localeStrings.NEEDS_ROUTED_TO + " "
    ));
    div.appendChild(strong);
    return div;
};
CaptureDisplay.prototype._generate_notes_line = function(payload) {
    var p = document.createElement("p");
    if (payload.reservation.note()) {
        p.innerHTML = "<strong>" + payload.reservation.note() + "</strong>";
    }
    return p;
};
CaptureDisplay.prototype._generate_patron_info = function(payload) {
    var p = document.createElement("p");
    p.innerHTML = "<strong>" + localeStrings.RESERVED + "</strong> " +
        formal_name(payload.reservation.usr()) + "<br />" +
        localeStrings.BARCODE + ": " +
        payload.reservation.usr().card().barcode();
    return p;
};
CaptureDisplay.prototype._generate_resv_info = function(payload) {
    var p = document.createElement("p");
    p.innerHTML = localeStrings.REQUEST + ": " +
        humanize_timestamp_string(payload.reservation.request_time()) +
        "<br />" + 
        localeStrings.DURATION + ": " +
        humanize_timestamp_string(payload.reservation.start_time()) +
        " - " + 
        humanize_timestamp_string(payload.reservation.end_time());
    return p;
};
CaptureDisplay.prototype._generate_meta_info = function(result) {
    var p = document.createElement("p");
    p.innerHTML = localeStrings.SLIP_DATE + ": " + result.servertime +
        "<br />" + localeStrings.PRINTED_BY + " " +
        formal_name(openils.User.user) + " " + localeStrings.AT + " " +
        fieldmapper.aou.findOrgUnit(openils.User.user.ws_ou()).shortname()
    return p;
};
CaptureDisplay.prototype.display_with_transit_info = function(result) {
    var div = document.createElement("div");
    var span = document.createElement("span");
    span.appendChild(document.createTextNode(localeStrings.CAPTURE_INFO));
    span.setAttribute("class", "capture_info");
    this.control_holder.appendChild(span);

    var button = document.createElement("button");
    button.setAttribute("class", "print_slip");
    button.setAttribute("type", "button");
    button.setAttribute("accesskey", localeStrings.PRINT_ACCESSKEY);
    button.innerHTML = localeStrings.PRINT;
    button.onclick = function() {
        try { dojo.byId("printing_iframe").contentWindow.print(); }
        catch (E) { alert(E); } /* XXX */
        return false;
    };
    this.control_holder.appendChild(button);

    div.appendChild(this._generate_transit_notice(result.payload));

    var p = document.createElement("p");
    p.appendChild(this._generate_route_line(result.payload));
    p.appendChild(this._generate_barcode_line(result.payload));
    p.appendChild(this._generate_title_line(result.payload));
    p.appendChild(this._generate_author_line(result.payload));
    div.appendChild(p);

    div.appendChild(this._generate_notes_line(result.payload));

    div.appendChild(this._generate_patron_info(result.payload));
    div.appendChild(this._generate_resv_info(result.payload));
    div.appendChild(this._generate_meta_info(result));

    this._create_iframe(div);
};
CaptureDisplay.prototype._create_iframe = function(contents) {
    var iframe = document.createElement("iframe");
    iframe.setAttribute("name", "printing_iframe");
    iframe.setAttribute("id", "printing_iframe");
    iframe.setAttribute("src", "");
    iframe.setAttribute("width", "100%");
    iframe.setAttribute("height", "400"); /* hardcode 400px? really? */

    this.data_holder.appendChild(iframe);

    var w = dojo.byId("printing_iframe").contentWindow;
    w.document.open();
    w.document.write(
        "<html><head><link rel='stylesheet' type='text/css' href='" +
        dojo.byId("booking_stylesheet_link").href +
        "' /><body></body></html>"
    );
    w.document.close();
    w.document.body.appendChild(contents);
    /* FIXME if (determine_autoprint_setting_somehow()) w.print(); */
};
CaptureDisplay.prototype.clear = function() {
    this.control_holder.innerHTML = "";
    this.data_holder.innerHTML = "";
};
CaptureDisplay.prototype.load = function(result) {
    try {
        this.control_holder.appendChild(document.createElement("hr"));
        if (!result.payload) {
            this.no_payload();
        } else if (!result.payload.fail_cause && result.payload.captured) {
            this.display_with_transit_info(result);
        } else {
            this.dump(result.payload);
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
        [openils.User.authtoken, barcode]
    );

    if (result && result.ilsevent !== undefined) {
        if (result.payload && result.payload.captured > 0) {
            capture_display.load(result);
            return CAPTURE_SUCCESS;
        } else {
            capture_display.load(result);
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
    init_auto_l10n(dojo.byId("auto_l10n_start_here"));
    capture_display = new CaptureDisplay(
        dojo.byId("capture_info_top"),
        dojo.byId("capture_info_bottom")
    );
}
