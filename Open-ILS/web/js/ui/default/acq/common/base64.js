dojo.require("dojox.encoding.base64");

function base64Encode(o) {
    return dojox.encoding.base64.encode(
        js2JSON(o).split("").map(function(c) { return c.charCodeAt(0); })
    );
}

function base64Decode(s) {
    return JSON2js(
        dojox.encoding.base64.decode(s).map(
            function(b) { return String.fromCharCode(b); }
        ).join("")
    );
}
