from mako import runtime, filters, cache
UNDEFINED = runtime.UNDEFINED
_magic_number = 2
_modified_time = 1198184806.6389661
_template_filename='/home/erickson/code/ILS/branches/acq-experiment/Open-ILS/web/oilsweb/oilsweb/templates/oils/default/acq/search.html'
_template_uri='oils/default/acq/search.html'
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
        context.write(u'\n\n')
        # SOURCE LINE 35
        context.write(u'\n\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_content(context):
    context.caller_stack.push_frame()
    try:
        c = context.get('c', UNDEFINED)
        _ = context.get('_', UNDEFINED)
        # SOURCE LINE 4
        context.write(u"\n    <form method='GET' action='pl_builder'>\n        <input type='hidden' name='ses' value='")
        # SOURCE LINE 6
        context.write(unicode(c.oils.core.authtoken))
        context.write(u"'/>\n        <div id='oils-acq-search-block' class='container'>\n            <div id='oils-acq-search-sources-block'>\n                <div id='oils-acq-search-sources-label'>")
        # SOURCE LINE 9
        context.write(unicode(_('Search Sources')))
        context.write(u"</div>\n                <select name='")
        # SOURCE LINE 10
        context.write(unicode(c.oils.acq.search_source_.cgi_name))
        context.write(u"' multiple='multiple' id='oils-acq-search-sources-selector'>\n                    <option value='native-evergreen-catalog'>")
        # SOURCE LINE 11
        context.write(unicode(_('Evergreen Catalog')))
        context.write(u"</option>\n                    <optgroup label='")
        # SOURCE LINE 12
        context.write(unicode(_("Z39.50 Sources")))
        context.write(u"'>\n")
        # SOURCE LINE 13
        for src,cfg in c.oils_z39_sources.iteritems():
            # SOURCE LINE 14
            context.write(u"                        <option value='")
            context.write(unicode(src))
            context.write(u"'>")
            context.write(unicode(src))
            context.write(u' ')
            context.write(unicode(cfg["host"]))
            context.write(u':')
            context.write(unicode(cfg["db"]))
            context.write(u'</option>\n')
        # SOURCE LINE 16
        context.write(u"                    </optgroup>\n                </select>\n            </div>\n            <div id='oils-acq-search-form-block'>\n                <table>\n")
        # SOURCE LINE 21
        for cls, lbl in c.oils_search_classes.iteritems():
            # SOURCE LINE 22
            context.write(u"                <tr class='oils-acq-search-form-row'>\n                    <td class='oils-acq-search-form-label'>")
            # SOURCE LINE 23
            context.write(unicode(lbl))
            context.write(u"</td>\n                    <td class='oils-acq-search-form-input'>\n                        <input name='")
            # SOURCE LINE 25
            context.write(unicode(cls))
            context.write(u"' size='24'/>\n                        <input type='hidden' name='")
            # SOURCE LINE 26
            context.write(unicode(c.oils.acq.search_class_.cgi_name))
            context.write(u"' value='")
            context.write(unicode(cls))
            context.write(u"'/>\n                    </td>\n                </tr>\n")
        # SOURCE LINE 30
        context.write(u"                </table>\n                <input type='submit' value='")
        # SOURCE LINE 31
        context.write(unicode(_("Submit")))
        context.write(u"'/>\n            </div>\n        </div>\n    </form>\n")
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_title(context):
    context.caller_stack.push_frame()
    try:
        _ = context.get('_', UNDEFINED)
        # SOURCE LINE 2
        context.write(unicode(_('Evergreen Acquisitions Search')))
        return ''
    finally:
        context.caller_stack.pop_frame()


