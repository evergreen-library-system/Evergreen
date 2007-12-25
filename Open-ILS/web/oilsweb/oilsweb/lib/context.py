from oilsweb.lib.util import childInit
import cgi

_context = None
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

class SubContext(object):
    ''' A SubContext is a class-specific context object that lives inside the global context object '''
    def _fields(self):
        ''' Returns all public fields for this subcontext '''
        return [ f for f in dir(self) if f[0:1] != '_' and 
            getattr(self, f).__class__.__name__.find('function') < 0  and
            getattr(self, f).__class__.__name__.find('method') < 0 ]

    def postinit(self):
        ''' Overide with any post-global-init initialization '''
        pass

class Context(object):
    ''' Global context object '''

    def __init__(self):
        self._fields = []

    def make_query_string(self):
        ''' Compiles a CGI query string from the collection of values 
            stored in the subcontexts '''

        q = ''
        for f in self._fields:
            if f.cgi_name:
                val = getattr(getattr(self, f.app), f.name)
                if val != f.default_value:
                    if isinstance(val, list):
                        for v in val:
                            if isinstance(val, str) or isinstance(val, unicode):
                                q += f.cgi_name+'='+cgi.escape(v)+'&'
                    else:
                        if isinstance(val, str) or isinstance(val, unicode):
                            q += f.cgi_name+'='+cgi.escape(val)+'&'

        if len(q) > 0: 
            q = q[:-1] # strip the trailing &

        return q

    @staticmethod
    def applySubContext(app, ctx):
        global _subContexts
        _subContexts[app] = ctx

    @staticmethod
    def getContext():
        global _context
        return _context

    @staticmethod
    def init(req):
        global _context, _subContexts
        c = _context = Context()
        childInit()

        for app, ctx in _subContexts.iteritems():
            ctx = ctx()
            setattr(c, app, ctx)
            for name in ctx._fields():
                item = getattr(ctx, name)
                item.app = app
                item.name = name
                c._fields.append(item)
                if item.cgi_name and item.cgi_name in req.params:
                    if item.multi:
                        setattr(getattr(c, app), name, req.params.getall(item.cgi_name))
                    else:
                        setattr(getattr(c, app), name, req.params[item.cgi_name])
                else:
                    setattr(getattr(c, app), name, item.default_value)

                # store the metatdata at <name>_
                setattr(getattr(c, app), "%s_" % name, item)

            ctx.postinit()

        return c

