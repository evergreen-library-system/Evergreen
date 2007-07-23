# -----------------------------------------------------------------------
# Copyright (C) 2007  Georgia Public Library Service
# Bill Erickson <billserickson@gmail.com>
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
# -----------------------------------------------------------------------

import re, md5


# -----------------------------------------------------------------------
# Grab-bag of general utility functions
# -----------------------------------------------------------------------


# -----------------------------------------------------------------------
# more succinct search/replace call
# -----------------------------------------------------------------------
def replace(str, pattern, replace):
   return re.compile(pattern).sub(replace, str)


def isEvent(evt):
    return (evt and isinstance(evt, dict) and evt.get('ilsevent') != None)

def eventCode(evt):
    if isEvent(evt):
        return evt['ilsevent']
    return None

def eventText(evt):
    if isEvent(evt):
        return evt['textcode']
    return None

      
def md5sum(str):
    m = md5.new()
    m.update(str)
    return m.hexdigest()

def unique(arr):
    ''' Unique-ify a list.  only works if list items are hashable '''
    o = {}
    for x in arr:
        o[x] = 1
    return o.keys()

