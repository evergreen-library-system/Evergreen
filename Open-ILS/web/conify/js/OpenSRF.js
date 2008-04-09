if(!dojo._hasResource['OpenSRF']){

	dojo._hasResource['OpenSRF'] = true;
	dojo.provide('OpenSRF');
	dojo.require('opensrf.opensrf', true);
	dojo.require('opensrf.opensrf_xhr', true);

	OpenSRF.session_cache = {};
	OpenSRF.CachedClientSession = function ( app ) {
		if (this.session_cache[app]) return this.session_cache[app];
		this.session_cache[app] = new OpenSRF.ClientSession ( app );
		return this.session_cache[app];
	}
}
