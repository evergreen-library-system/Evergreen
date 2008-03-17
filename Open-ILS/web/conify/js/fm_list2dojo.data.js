
function _toHash () {
	var _hash = {};
	for ( var i in fmclasses['aou']) _hash[i] = this[i]();
	return _hash;
}
	
aou.prototype.toHash = _toHash;

