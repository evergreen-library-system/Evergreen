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

import osrf.log
import osrf.system
from oils.utils.idl import IDLParser
from oils.utils.csedit import oilsLoadCSEditor

class System(object):

    @staticmethod
    def connect(**kwargs):
        """
        Connects to the OpenSRF network, parses the IDL, and loads the CSEditor.
        """

        osrf.system.System.connect(**kwargs)
        IDLParser.parse()
        oilsLoadCSEditor()

    @staticmethod
    def remote_connect(**kwargs):
        """
        Connects to the OpenSRF network, parses the IDL, and loads the CSEditor.

        This version of connect does not talk to opensrf.settings, which means
        it also does not connect to the OpenSRF cache.
        """

        osrf.system.System.net_connect(**kwargs)
        IDLParser.parse()
        oilsLoadCSEditor()
