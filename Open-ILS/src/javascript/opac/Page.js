/* Top level page object.  All pages descend from this class */

function Page() {
	debug("Somebody called Page() constructor...");
}


Page.prototype.init = function() {
	debug("Falling back to Page.init()");
}

/* override me */
Page.prototype.instance = function() {
	throw new EXAbstract(
			"instance() must be overridden by all Page subclasses");
}
