function EX(message) {
	this.init(message);
}

EX.prototype.init = function(message) {
	this.message = message;
}

EX.prototype.toString = function() {
	return "Exception Occured \n" + this.message;
}

EXCommunication.prototype					= new EX();
EXCommunication.prototype.constructor	= EXCommunication;
EXCommunication.baseClass					= EX.prototype;

function EXCommunication(message) {
	this.init("EXCommunication: " + message);
}
