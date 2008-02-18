from oilsweb.lib.util import childInit
import cgi

# global context
_context = None
# global collection of sub-contexts
_subContexts = {}

class ContextItem(object):
    ''' Defines a single field on a subcontext object. '''
    def __init__(self, **kwargs):
        self.app = None
        self.name = kwargs.get('name')
        self.cgi_name = kwargs.get('cgi_name')
        self.default_value = kwargs.get('default_value')
        self.qname = None
        self.multi = kwargs.get('multi')
        self.session = kwargs.get('session')
        self.value = self.default_value

class SubContext(object):
    ''' A SubContext is a class-specific context object that lives inside the global context object '''
    def _fields(self):
        ''' Returns all public fields for this subcontext '''
        return [ f for f in dir(self) if f[0:1] != '_' and 
            getattr(self, f).__class__.__name__.find('method') < 0 ]

    def postinit(self):
        ''' Overide with any post-global-init initialization '''
        pass

class Context(object):
    ''' Global context object '''

    def __init__(self):
        self._fields = []
        self._req = None
        self._resp = None

    def make_query_string(self):
        ''' Compiles a CGI query string from the collection of values 
            stored in the subcontexts '''

        q = ''
        for f in self._fields:
            if f.cgi_name and not f.session:
                val = f.value
                if val != f.default_value:
                    if isinstance(val, list):
                        for v in val:
                            if isinstance(val, str) or isinstance(val, unicode):
                                q += f.cgi_name+'='+cgi.escape(v)+'&'
                    else:
                        if isinstance(val, str) or isinstance(val, unicode):
                            q += f.cgi_name+'='+cgi.escape(val)+'&'

        return q[:-1] # strip the trailing &

    def apply_session_vars(self):
        from oilsweb.lib.base import session
        for f in self._fields:
            if f.cgi_name and f.session:
                val = f.value
                if val is not None and val != f.default_value:
                    session[f.cgi_name] =  val

    @staticmethod
    def apply_sub_context(app, ctx):
        global _subContexts
        _subContexts[app] = ctx

    @staticmethod
    def get_context():
        global _context
        return _context

    @staticmethod
    def init(req, resp):
        global _context, _subContexts
        from oilsweb.lib.base import session
        c = _context = Context()
        c._req = req
        c._resp = resp
        childInit()

        for app, ctx in _subContexts.iteritems():
            ctx = ctx()
            setattr(c, app, ctx)
            for name in ctx._fields():

                item = getattr(ctx, name)
                item.app = app
                item.name = name
                c._fields.append(item)

                # -------------------------------------------------------------------
                # Load the cgi/session data.  First try the URL params, then try the
                # session cache, and finally see if the data is in a cookie.  If 
                # no data is found, use the default
                # -------------------------------------------------------------------
                if item.cgi_name:
                    if item.cgi_name in req.params:
                        if item.multi:
                            item.value = req.params.getall(item.cgi_name)
                        else:
                            item.value = req.params[item.cgi_name]
                    else:
                        if item.session:
                            if item.cgi_name in session:
                                item.value = session[item.cgi_name]
                                set = True
                            else:
                                if item.cgi_name in req.cookies:
                                    item.value = req.cookies[item.cgi_name]

        # run postinit after all contexts have been loaded
        for app in _subContexts.keys():
            ctx = getattr(c, app)
            ctx.postinit()

        return c
