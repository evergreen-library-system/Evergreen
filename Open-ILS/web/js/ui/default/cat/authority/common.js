function render_control_set_metadata(control_set) {
    var anchor = dojo.byId("control-set-metadata");
    anchor.href = oilsBasePath + "/cat/authority/control_set?focus=" +
        control_set.id();
    anchor.innerHTML = dojo.string.substitute(
        localeStrings.CONTROL_SET_METADATA, [
            control_set.id(), control_set.name(), control_set.description()
        ]
    );
    openils.Util.show("control-set-metadata-holder");
}
