#!/usr/bin/env python
import xml.dom.minidom
import optparse

def merge_events(master, localization):
    """
    Merge two event definition files
    """

    master_xml = xml.dom.minidom.parse(master)
    l10n_xml = xml.dom.minidom.parse(localization)
    impl = xml.dom.minidom.getDOMImplementation()

    merged = impl.createDocument(None, 'ils_events', None)

    # Add notes
    notes = master_xml.getElementsByTagName('notes')[0]
    merged.documentElement.appendChild(notes)

    events = master_xml.getElementsByTagName('event')
    for event in events:
        try: 
            code = event.getAttribute('code')
            merged.documentElement.appendChild(merged.createTextNode("\n"))
            l10n_node = get_l10n_event_desc(l10n_xml, code)
            for child in event.childNodes:
                if child.nodeName == 'desc':
                    if child.getAttribute('xml:lang') == l10n_node.getAttribute('xml:lang'):
                        event.removeChild(child)
            event.appendChild(l10n_node)
            merged.documentElement.appendChild(event)
            merged.documentElement.appendChild(merged.createTextNode("\n"))
        except AttributeError:
            print("%s probably has an <event> [%s] without a matching <desc> node" % (localization, code))

    return merged

def get_l10n_event_desc(l10n_xml, code):
    """
    Gets a localized event description
    """

    desc_nodes = ''

    events = l10n_xml.getElementsByTagName('event')
    for event in events:
        if event.getAttribute('code') == code:
            for node in event.childNodes:
                if node.nodeName == 'desc':
                    return node
        else:
            continue
            
def main():
    """
    Determine what action to take
    """
    opts = optparse.OptionParser()
    opts.add_option('-m', '--master', action='store', \
        help='Master ils_events.xml file into which we are merging our additional localized strings', \
        metavar='FILE')
    opts.add_option('-l', '--localization', action='store', \
        help='Localized ils_events.xml file', \
        metavar='FILE')
    opts.add_option('-o', '--output', dest='outfile', \
        help='Write output to FILE (defaults to STDOUT)', metavar='FILE')
    opts.add_option('-p', '--pretty', action='store', \
        help='Write pretty XML output')
    (options, args) = opts.parse_args()

    if not options.master:
        opts.error('Must specify the master ils_events file (-m option)')
    elif not options.localization:
        opts.error('Must specify the localized ils_events file to merge (-l option)')
    else:
        merged = merge_events(options.master, options.localization)

    if options.outfile:
        outfile = open(options.outfile, 'w')
        if options.pretty:
            outfile.write(merged.toprettyxml(encoding='utf-8'))
        else:
            outfile.write(merged.toxml(encoding='utf-8'))
    else:
        if options.pretty:
            print merged.toprettyxml(encoding='utf-8')
        else:
            print merged.toxml(encoding='utf-8')

if __name__ == '__main__':
    main()

# vim:et:ts=4:sw=4: 
