from mako import runtime, filters, cache
UNDEFINED = runtime.UNDEFINED
_magic_number = 2
_modified_time = 1198177152.534961
_template_filename='/home/erickson/code/ILS/branches/acq-experiment/Open-ILS/web/oilsweb/oilsweb/templates/oils/default/acq/pl_builder.html'
_template_uri='oils/default/acq/pl_builder.html'
_template_cache=cache.Cache(__name__, _modified_time)
_source_encoding=None
_exports = ['block_content', 'block_title']


def _mako_get_namespace(context, name):
    try:
        return context.namespaces[(__name__, name)]
    except KeyError:
        _mako_generate_namespaces(context)
        return context.namespaces[(__name__, name)]
def _mako_generate_namespaces(context):
    pass
def _mako_inherit(template, context):
    _mako_generate_namespaces(context)
    return runtime._inherit_from(context, u'../base.html', _template_uri)
def render_body(context,**pageargs):
    context.caller_stack.push_frame()
    try:
        __M_locals = dict(pageargs=pageargs)
        # SOURCE LINE 1
        context.write(u'\n')
        # SOURCE LINE 2
        context.write(u'\n')
        # SOURCE LINE 21
        context.write(u'\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_content(context):
    context.caller_stack.push_frame()
    try:
        c = context.get('c', UNDEFINED)
        _ = context.get('_', UNDEFINED)
        # SOURCE LINE 3
        context.write(u"\n    <table id='oils-acq-pl_builder-table'>\n        <thead>\n            <tr><td>")
        # SOURCE LINE 6
        context.write(unicode(_('Title')))
        context.write(u'</td><td>')
        context.write(unicode(_('Author')))
        context.write(u'</td><td>')
        context.write(unicode(_('Source')))
        context.write(u'</td></tr>\n        </thead>\n        <tbody>\n')
        # SOURCE LINE 9
        for res in c.oils_acq_records:
            # SOURCE LINE 10
            for rec in res['records']:
                # SOURCE LINE 11
                context.write(u"                <tr>\n                    <td><input type='checkbox' name='")
                # SOURCE LINE 12
                context.write(unicode(c.oils.acq.picked_records_.cgi_name))
                context.write(u"' value='blah'/></td>\n                    <td>")
                # SOURCE LINE 13
                context.write(unicode(rec['extracts']["bibdata.title"]))
                context.write(u'</td>\n                    <td>')
                # SOURCE LINE 14
                context.write(unicode(rec['extracts']["bibdata.author"]))
                context.write(u'</td>\n                    <td>')
                # SOURCE LINE 15
                context.write(unicode(res['service']))
                context.write(u'</td>\n                </tr>\n')
        # SOURCE LINE 19
        context.write(u'        </tbody>\n    </table>\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_title(context):
    context.caller_stack.push_frame()
    try:
        _ = context.get('_', UNDEFINED)
        # SOURCE LINE 2
        context.write(unicode(_('Evergreen Acquisitions Results')))
        return ''
    finally:
        context.caller_stack.pop_frame()


