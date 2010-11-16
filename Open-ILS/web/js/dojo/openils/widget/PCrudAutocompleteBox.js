if (!dojo._hasResource["openils.widget.PCrudAutocompleteBox"]) {
    dojo._hasResource["openils.widget.PCrudAutocompleteBox"] = true;
    dojo.provide("openils.widget.PCrudAutocompleteBox");

    dojo.require("openils.PermaCrud.Store");
    dojo.require("dijit.form.FilteringSelect");

    dojo.declare(
        "openils.widget.PCrudAutocompleteBox", [dijit.form.FilteringSelect], {
        //  summary:
        //      An autocompleting textbox that uses PermaCrud to fetch
        //      matches. openils.PermaCrud.Store does the work.
        //
        //  description:
        //      Use just like a dijit.form.FilteringSelect except that there
        //      are these additional properties supported in the args object:
        //
        //      The *fmclass* parameter.
        //          The class hint for the kind of fieldmapper object you
        //          want to work with. From the IDL.
        //
        //      The *store_options* parameter.
        //          Another object of options such as you would pass to
        //          openils.PermaCrud.Store. See the documentation for that
        //          class (it's more thorough).
        //
        //      You should also use the existing *searchAttr* object to
        //      specify what you want to search for as you type and what
        //      you see in the box.
            "store": "",
            "fmclass": "",
            "store_options": {},

            "constructor": function(args) {
                if (!args.hasDownArrow)
                    args.hasDownArrow = false;

                if (!args.store) {
                    if (!args.fmclass)
                        throw new Error("need either store or fmclass");
                    var store_options = dojo.mixin(
                        {"fmclass": args.fmclass}, args.store_options
                    );
                    args.store = new openils.PermaCrud.Store(store_options);
                }
            }
        }
    );
}
