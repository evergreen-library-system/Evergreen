#!/usr/bin/env python
# vim: set fileencoding=utf-8 :
# vim:et:ts=4:sw=4:

# Copyright (C) 2008 Laurentian University
# Dan Scott <dscott@laurentian.ca>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

"""
The MARC editor offers tooltips generated from the Library of Congress Concise
MARC Record documentation available online.

This script generates a French version of those tooltips based on the Library
and Archives Canada translation of the LoC documentation.
"""

from BeautifulSoup import BeautifulSoup

# Simple case:
# Get <a id="#mrcb(###)">: map $1 to tag attribute
#   From within that A event, retrieve the SMALL event
#     If SMALL.cdata == '\s*(R)\s*' then repeatable = yes  
#     If SMALL.cdata == '\s*(NR)\s*' then repeatable = no
#   Get the next P event: map to <description> element
#
# Target:
#  <field repeatable="true" tag="006">
#    <description>This field contains 18 character positions (00-17)
#    that provide for coding information about special aspects of
#    the item being cataloged that cannot be coded in field 008
#    (Fixed-Length Data Elements). It is used in cases when an item
#    has multiple characteristics. It is also used to record the coded
#    serial aspects of nontextual continuing resources.</description>
#  </field>

# Complex case:

# field and tag and repeatable description as above
# check for <h3>Indicateurs</h3> before next <h2>
#   check for <li>Premier indicateur or <li>Second indicateur to set indicator.position
#   check for <li class="sqf">(\d)\s*-\s*([^<]*)< for indicator.position.value = def__init__ion
#   ignore if "Non d&#233;fini"
# check for <h3>Codes do sous-zones
#   for each <li>:
#     CDATA (stripped of tags, with (NR) or (R) stripped out) = field.subfield.def__init__ion
#     (NR) or (R) means field.subfield.repeatable = false or true

#  <field repeatable="true" tag="800">
#    <description>An author/title series added entry in which the
#      author portion is a personal name.</description>
#    <indicator position="1" value="0">
#      <description>Forename</description>
#    </indicator>
#    <indicator position="1" value="1">
#      <description>Surname</description>
#    </indicator>
#    <indicator position="1" value="3">
#      <description>Family name</description>
#    </indicator>
#    <subfield code="a" repeatable="false">
#      <description>Personal name </description>
#    </subfield>
#    <subfield code="b" repeatable="false">
#      <description>Numeration </description>
#    </subfield>

class MarcCollection(object):
    """
    Contains a set of descriptions of MARC fields organized by tag
    """
    
    def __init__(self):
        self.fields = {}

    def add_field(self, field):
        """
        Add a MARC field to our collection
        """
        self.fields[field.tag] = field

    def to_xml(self):
        """
        Convert the MARC field collection to XML representation
        """
        xml = "<?xml version='1.0' encoding='utf-8'?>\n"
        xml += "<fields>\n"
        keys = self.fields.keys()
        keys.sort()
        for key in keys:
            xml += self.fields[key].to_xml()
        xml += "\n</fields>\n"
        return xml

class MarcField(object):
    """
    Describes the properties of a MARC field

    You can directly access and manipulate the indicators and subfields lists
    """
    def __init__(self, tag, name, repeatable, description):
        self.tag = tag
        self.name = name
        self.repeatable = repeatable
        self.description = description
        self.indicators = []
        self.subfields = []

    def to_xml(self):
        """
        Convert the MARC field to XML representation
        """
        xml = u"  <field repeatable='%s' tag='%s'>\n" % (self.repeatable, self.tag)
        xml += u"    <name>%s</name>\n" % (self.name)
        xml += u"    <description>%s</description>\n" % (self.description)
        for ind in self.indicators:
            xml += ind.to_xml()
            xml += '\n'
        for subfield in self.subfields:
            xml += subfield.to_xml()
            xml += '\n'
        xml += u"  </field>\n"

        return xml

class Subfield(object):
    """
    Describes the properties of a MARC subfield
    """
    def __init__(self, code, repeatable, description):
        self.code = code
        self.repeatable = repeatable
        self.description = description

    def to_xml(self):
        """
        Convert the subfield to XML representation
        """
        xml = u"    <subfield code='%s' repeatable='%s'>\n" % (self.code, self.repeatable)
        xml += u"      <description>%s</description>\n" %  (self.description)
        xml += u"    </subfield>\n"
        return xml
  
class Indicator(object):
    """
    Describes the properties of an indicator-value pair for a MARC field
    """
    def __init__(self, position, value, description):
        self.position = position
        self.value = value
        self.description = description

    def to_xml(self):
        """
        Convert the indicator-value pair to XML representation
        """
        xml = u"    <indicator position='%s' value='%s'>\n" % (self.position, self.value)
        xml += u"      <description>%s</description>\n" %  (self.description)
        xml += u"    </indicator>\n"
        return xml
 
def process_indicator(field, position, raw_ind):
    """
    Given an XML chunk holding indicator data,
    append Indicator objects to a MARC field
    """
    if (re.compile(r'indicateur\s*-\s*Non').search(raw_ind.contents[0])):
        return None
    if (not raw_ind.ul):
        print "No %d indicator for %s, although not not defined either..." % (position, field.tag)
        return None
    ind_values = raw_ind.ul.findAll('li')
    for value in ind_values:
        text = ''.join(value.findAll(text=True))
        if (re.compile(u'non précisé').search(text)):
            continue
        matches = re.compile(r'^(\S(-\S)?)\s*-\s*(.+)$', re.S).search(text)
        if matches is None: 
            continue
        new_ind = Indicator(position, matches.group(1).replace('\n', ' ').rstrip(), matches.group(3).replace('\n', ' ').rstrip())
        field.indicators.append(new_ind)

def process_subfield(field, subfield):
    """
    Given an XML chunk holding subfield data,
    append a Subfield object to a MARC field
    """
    repeatable = 'true'

    if (subfield.span):
        if (re.compile(r'\(R\)').search(subfield.span.renderContents())):
            repeatable = 'false'
        subfield.span.extract()
    elif (subfield.small):
        if (re.compile(r'\(R\)').search(subfield.small.renderContents())):
            repeatable = 'false'
        subfield.small.extract()
    else:
        print "%s has no small or span tags?" % (field.tag)

    subfield_text = re.compile(r'\n').sub(' ', ''.join(subfield.findAll(text=True)))
    matches = re.compile(r'^\$(\w)\s*-\s*(.+)$', re.S).search(subfield_text)
    if (not matches):
        print "No subfield match for field: " + field.tag
        return None
    field.subfields.append(Subfield(matches.group(1).replace('\n', ' ').rstrip(), repeatable, matches.group(2).replace('\n', ' ').rstrip()))

def process_tag(tag):
    """
    Given a chunk of XML representing a MARC field, generate a MarcField object
    """
    repeatable = 'true'
    name = u''
    description = u''

    # Get tag
    tag_num = re.compile(r'^mrcb(\d+)').sub(r'\1', tag['id'])
    if (len(tag_num) != 3):
        return None

    # Get repeatable - most stored in <span>, some stored in <small>
    if (re.compile(r'\(NR\)').search(tag.renderContents())):
        repeatable = 'false'

    # Get name - stored in <h2> like:
    # <h2><a id="mrcb250">250 - Mention d'&#233;dition <span class="small">(NR)</span></a>
    name = re.compile(r'^.+?-\s*(.+)\s*\(.+$', re.S).sub(r'\1', ''.join(tag.findAll(text=True)))
    name = name.replace('\n', ' ').rstrip()

    # Get description
    desc = tag.parent.findNextSibling('p')
    if (not desc):
        print "No description for %s" % (tag_num)
    else:
        if (str(desc.__class__) == 'BeautifulSoup.Tag'):
            try:
                description += u''.join(desc.findAll(text=True))
            except:
                print "Bad description for: " + tag_num
                print u' '.join(desc.findAll(text=True))
        else:
            description += desc.string
    description = description.replace('\n', ' ').rstrip()

    # Create the tag
    field = MarcField(tag_num, name, repeatable, description)

    for desc in tag.parent.findNextSiblings():
        if (str(desc.__class__) == 'BeautifulSoup.Tag'):
            if (desc.name == 'h2'):
                break
            elif (desc.name == 'h3' and re.compile(r'Indicateurs').search(desc.string)):
                # process indicators
                first_ind = desc.findNextSibling('ul').li
                second_ind = first_ind.findNextSibling('li')
                if (not second_ind):
                    second_ind = first_ind.parent.findNextSibling('ul').li
                process_indicator(field, 1, first_ind)
                process_indicator(field, 2, second_ind)
            elif (desc.name == 'h3' and re.compile(r'Codes de sous').search(desc.string)):
                # Get subfields
                subfield = desc.findNextSibling('ul').li
                while (subfield):
                    process_subfield(field, subfield)
                    subfield = subfield.findNextSibling('li')

    return field

if __name__ == '__main__':
    import codecs
    import copy
    import os
    import re
    import subprocess

    ALL_MY_FIELDS = MarcCollection()

    # Run through the LAC-BAC MARC files we care about and convert like crazy   
    for filename in os.listdir('.'):

        if (not re.compile(r'^040010-1\d\d\d-f.html').search(filename)):
            continue
        print filename
        devnull = codecs.open('/dev/null', encoding='utf-8', mode='w')
        file = subprocess.Popen(
            ('tidy', '-asxml', '-n', '-q', '-utf8', filename),
            stdout=subprocess.PIPE, stderr=devnull).communicate()[0]

        # Strip out the hard spaces on our way through
        hardMassage = [(re.compile(r'&#160;'), lambda match: ' ')]
        myHardMassage = copy.copy(BeautifulSoup.MARKUP_MASSAGE)
        myHardMassage.extend(myHardMassage)

        filexml = BeautifulSoup(file, markupMassage=myHardMassage)

        tags = filexml.findAll('a', id=re.compile(r'^mrcb'))
        for tag in tags:
            field = process_tag(tag)
            if (field):
                ALL_MY_FIELDS.add_field(field)

    MARCOUT = codecs.open('marcedit-tooltips-fr.xml', encoding='utf-8', mode='w')
    MARCOUT.write(ALL_MY_FIELDS.to_xml().encode('UTF-8'))
    MARCOUT.close()
