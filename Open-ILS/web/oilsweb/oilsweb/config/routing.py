"""Routes configuration

The more specific and detailed routes should be defined first so they
may take precedent over the more generic routes. For more information
refer to the routes manual at http://routes.groovie.org/docs/
"""
from pylons import config
from routes import Mapper

def make_map():
    """Create, configure and return the routes Mapper"""
    map = Mapper(directory=config['pylons.paths']['controllers'],
                 always_scan=config['debug'])

    # The ErrorController route (handles 404/500 error pages); it should
    # likely stay at the top, ensuring it can always be resolved
    map.connect('error/:action/:id', controller='error')

    # CUSTOM ROUTES HERE

    prefix = ''
    if not config.get('use_mod_python'):
        prefix = 'oils/'

    map.connect(prefix+':controller/:action')
    map.connect(prefix+':controller/:action/:id')
    map.connect(prefix+'admin/:action/:type/:id', controller='admin')
    map.connect(prefix+'admin/:action/:type', controller='admin')

    map.connect('osrf-http-translator', controller='translator', action='proxy')

    ''' trying a different set of admin routes above...
    map.connect('acq_admin', 'oils/admin', controller='acq_admin')
    map.connect('acq_admin_object', 'oils/admin/:object', controller='acq_admin')
    map.connect('acq_admin_direct', 'oils/admin/direct/:object/:id', controller='acq_admin')
    '''
    map.connect('*url', controller='template', action='view')

    return map
