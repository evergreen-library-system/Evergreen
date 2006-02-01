
function containerDoRequest( req, callback, args ) {

	if( callback ) {
		req.callback( callback );
		req.request.args = args;
		req.send();
		return null;
	}

	req.send(true); 
	return req.result();
}


function containerFetchAll( callback, args ) {
	var req = new Request( 
		FETCH_CONTAINERS, G.user.session, G.user.id(), 'biblio', 'bookbag' );
	return containerDoRequest( req, callback, args );
}

function containerFlesh( id, callback, args ) {
	var req = new Request( FLESH_CONTAINER, G.user.session, 'biblio', id );                                                                                               
	return containerDoRequest( req, callback, args );
}

function containerDelete( id, callback, args ) {
	var req = new Request( DELETE_CONTAINER, G.user.session, 'biblio', id );
	return containerDoRequest(req, callback, args );
}


function containerCreate( name, pub, callback, args ) {

	var container = new cbreb();
	container.btype('bookbag');
	container.owner( G.user.id() );
	container.name( name );
	if(pub) container.pub(1);

	var req = new Request( 
		CREATE_CONTAINER, G.user.session, 'biblio', container );
	return containerDoRequest( req, callback, args );
}

function containerCreateItem( containerId, target, callback, args ) {

	var item = new cbrebi();
	item.target_biblio_record_entry(target);
	item.bucket(containerId);

	var req = new Request( CREATE_CONTAINER_ITEM, 
		G.user.session, 'biblio', item );

	return containerDoRequest( req, callback, args );
}

function containerRemoveItem( id, callback, args ) {
	var req = new Request( DELETE_CONTAINER_ITEM, G.user.session, 'biblio', id );
	return containerDoRequest( req, callback, args );
}
