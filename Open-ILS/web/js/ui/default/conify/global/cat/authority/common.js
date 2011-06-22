/* To be used by interfaces for editing child tables of acs. */
function render_control_set_metadata(control_set) {
    var anchor = dojo.byId("control-set-metadata");
    anchor.href = oilsBasePath +
        "/conify/global/cat/authority/control_set?focus=" + control_set.id();
    anchor.innerHTML = dojo.string.substitute(
        localeStrings.CONTROL_SET_METADATA, [
            control_set.id(), control_set.name(), control_set.description()
        ]
    );
    openils.Util.show("control-set-metadata-holder");
}

/* To be used by interfaces for editing child tables of acsaf.  They not
 * only want to know what acsaf they belong to, but for convenience they
 * should also have handy the acs id to which their parent acsaf belongs,
 * so they can provide the most helpful "back" link.
 */
function render_authority_field_metadata(authority_field, control_set_id) {
    var anchor = dojo.byId("authority-field-metadata");
    var href = oilsBasePath +
        "/conify/global/cat/authority/control_set_authority_field?focus=" +
        authority_field.id();
    if (control_set_id) href += "&acs=" + control_set_id;

    anchor.href = href;
    anchor.innerHTML = dojo.string.substitute(
        localeStrings.AUTHORITY_FIELD_METADATA, [
            "id", "tag", "sf_list", "name", "description"
        ].map(function(k) {
            var v = authority_field[k]();
            return (v == null) ? "" : v;
        })
    );
    openils.Util.show("authority-field-metadata-holder");
}
