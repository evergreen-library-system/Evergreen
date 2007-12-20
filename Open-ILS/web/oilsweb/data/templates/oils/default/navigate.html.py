from mako import runtime, filters, cache
UNDEFINED = runtime.UNDEFINED
_magic_number = 2
_modified_time = 1198108479.9635
_template_filename=u'/home/erickson/code/sandbox/python/pylons/oilsweb/oilsweb/templates/oils/default/navigate.html'
_template_uri=u'oils/default/acq/../navigate.html'
_template_cache=cache.Cache(__name__, _modified_time)
_source_encoding=None
_exports = []


def render_body(context,**pageargs):
    context.caller_stack.push_frame()
    try:
        __M_locals = dict(pageargs=pageargs)
        c = context.get('c', UNDEFINED)
        _ = context.get('_', UNDEFINED)
        # SOURCE LINE 1
        context.write(u"<table id='oils-base-navigate-table'>\n    <tbody>\n        <tr><td><a href='index?")
        # SOURCE LINE 3
        context.write(unicode(c.oils.make_query_string()))
        context.write(u"'>")
        context.write(unicode(_('Home')))
        context.write(u"</a></td></tr>\n        <tr><td><a href='search?")
        # SOURCE LINE 4
        context.write(unicode(c.oils.make_query_string()))
        context.write(u"'>")
        context.write(unicode(_('Search')))
        context.write(u'</a></td></tr>\n    </tbody>\n</table>\n\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


