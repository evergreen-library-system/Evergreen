function Request(type) {
	var s = type.split(":");
	this.request = new RemoteRequest(s[0], s[1]);
	for( var x = 1; x!= arguments.length; x++ ) 
		this.request.addParam(arguments[x]);
}

Request.prototype.callback = function(cal) { this.request.setCallback(cal); }
Request.prototype.send		= function(block){this.request.send(block);}
Request.prototype.result	= function(){return this.request.getResultObject();}
