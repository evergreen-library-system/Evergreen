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
        merged.documentElement.appendChild(event)
        event.appendChild(get_l10n_event_desc(l10n_xml, event.getAttribute('code')))

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
    (options, args) = opts.parse_args()

    if not options.master:
        opts.error('Must specify the master ils_events file (-m option)')
    elif not options.localization:
        opts.error('Must specify the localized ils_events file to merge (-l option)')
    else:
        merged = merge_events(options.master, options.localization)

    if options.outfile:
        outfile = open(options.outfile, 'w')
        outfile.write(merged.toprettyxml(encoding='utf-8'))
    else:
        print merged.toprettyxml(encoding='utf-8')

if __name__ == '__main__':
    main()

# vim:et:ts=4:sw=4: 
