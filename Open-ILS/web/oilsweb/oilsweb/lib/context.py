from oilsweb.lib.util import childInit
import pylons.config
import cgi

_context = None
_subContexts = {}

class ContextItem(object):
    def __init__(self, **kwargs):
        self.app = None
        self.name = kwargs.get('name')
        self.cgi_name = kwargs.get('cgi_name')
        self.default_value = kwargs.get('default_value')
        self.qname = None
        self.multi = kwargs.get('multi')

class Context(object):
    def __init__(self):
        self._fields = []

    def wrap(self):
        return {'oils': self}

    '''
    def applySubContext(self, app, subContext):
        setattr(self, app, subContext)
    '''

    def make_query_string(self):
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
        if len(q) > 0: q = q[:-1] # strip the trailing &
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

                # store the metatdata at _<name>
                setattr(getattr(c, app), "%s_" % name, item)

        c.core.prefix = pylons.config['oils_prefix']
        c.core.media_prefix = pylons.config['oils_media_prefix']
        c.core.ac_prefix = pylons.config['oils_added_content_prefix']

        c.core.skin = 'default' # XXX
        c.core.theme = 'default' # XXX

        return c


class SubContext(object):
    def _fields(self):
        return [ f for f in dir(self) if f[0:1] != '_' ]

class CoreContext(SubContext):
    def __init__(self):
        self.prefix = ContextItem()
        self.media_prefix = ContextItem()
        self.ac_prefix = ContextItem()
        self.skin = ContextItem()
        self.theme = ContextItem()
        self.authtoken = ContextItem(cgi_name='ses')
Context.applySubContext('core', CoreContext)

