Function.prototype.method = function (name, func) {
    this.prototype[name] = func;
    return this;
}

Function.method('inherits', function (parent) {
    var d = 0, p = (this.prototype = new parent());
    this.constructor = this;
    this.prototype.superclass = parent;
    this.method('uber', function uber(name) {
        var f, r, t = d, v = parent.prototype;
        if (t) {
            while (t) {
                v = v.constructor.prototype;
                t -= 1;
            }
            f = v[name];
        } else {
            f = p[name];
            if (f == this[name]) {
                f = v[name];
            }
        }
        d += 1;
        r = f.apply(this, Array.prototype.slice.apply(arguments, [1]));
        d -= 1;
        return r;
    });
    return this;
});


instance_of = function(o, c) {
	while (o != null) {
		if (o.constructor === c) {
			return true;
		}
		if (o === Object) {
			return false;
		}
		o = o.superclass;
	}
	return false;
};


