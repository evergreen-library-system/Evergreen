function EX(message) {
	this.init(message);
}

EX.prototype.init = function(message) {
	this.message = message;
}

EX.prototype.toString = function() {
	return "\n *** Exception Occured \n" + this.message;
}

EXCommunication.prototype					= new EX();
EXCommunication.prototype.constructor	= EXCommunication;
EXCommunication.baseClass					= EX.prototype.constructor;

function EXCommunication(message) {
	this.init("EXCommunication: " + message);
}


EXArg.prototype					= new EX();
EXArg.prototype.constructor	= EXArg;
EXArg.baseClass					= EX.prototype.constructor;

function EXArg(message) {
	this.init("EXArg: " + message);
}


EXAbstract.prototype					= new EX();
EXAbstract.prototype.constructor	= EXAbstract;
EXAbstract.baseClass					= EX.prototype.constructor;

function EXAbstract(message) {
	this.init("EXAbstract: " + message);
}
