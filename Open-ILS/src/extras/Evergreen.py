"""
Evergreen IRC Interface plugin for supybot
"""

import supybot

import urllib
import xml.dom.minidom
import re

__revision__ = "$Id$"
__author__ = 'PINES'
__contributors__ = {}

import supybot.conf as conf
import supybot.utils as utils
from supybot.commands import *
import supybot.plugins as plugins
import supybot.ircutils as ircutils
import supybot.ircmsgs as ircmsgs
import supybot.privmsgs as privmsgs
import supybot.registry as registry
import supybot.callbacks as callbacks

def configure(advanced):
    from supybot.questions import expect, anything, something, yn
    conf.registerPlugin('Evergreen', True)

conf.registerPlugin('Evergreen')

class Evergreen(callbacks.PrivmsgCommandAndRegexp):
    threaded = True
    def __init__(self):
        self.__parent = super(Evergreen, self)
        self.__parent.__init__()
        #super(Evergreen, self).__init__()

    def callCommand(self, name, irc, msg, *L, **kwargs):
        self.__parent.callCommand(name, irc, msg, *L, **kwargs)

    def osearch(self, irc, msg, args, word):
        """<terms>

        Performs an OpenSearch against Evergreen for <terms>.
        """
        url = 'http://192.168.2.112/opensearch/?target=mr_result&mr_search_type=keyword&mr_search_query=' + urllib.quote(word) + '&page=1&mr_search_depth=0&mr_search_location=1&pagesize=5&max_rank=100'
        irc.reply( 'Searching for ' + word + '...' );
        rss = urllib.urlopen( url )
        dom = xml.dom.minidom.parseString( rss.read() )
        regexp = re.compile(r'http://tinyurl.com/\w+');
        for item in dom.getElementsByTagName('item'):
            title = item.getElementsByTagName('title')[0]
            link = item.getElementsByTagName('link')[0]
            f = urllib.urlopen('http://tinyurl.com/create.php?url='+link.firstChild.data)
            tiny = regexp.search( f.read() ).group(0)
            s = title.firstChild.data
            s += " | " + tiny
            irc.reply( s )

    osearch = wrap(osearch, ['Text'])
Class = Evergreen
