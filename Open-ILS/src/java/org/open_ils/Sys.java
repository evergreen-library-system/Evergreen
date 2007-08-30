package org.open_ils;

import org.opensrf.*;
import org.opensrf.util.*;
import org.open_ils.*;
import org.open_ils.idl.*;
import org.opensrf.util.*;

import java.util.Map;
import java.util.HashMap;
import java.io.IOException;


public class Sys {

    private static IDLParser idlParser = null;

    public static void init(Map<String, String> attrs) throws ConfigException, SessionException, IOException, IDLException {

        String configFile = attrs.get("configFile");
        String configContext = attrs.get("configContext");
        String logProto = attrs.get("logProtocol");
        String logFile = attrs.get("logFile");
        String logLevel = attrs.get("logLevel");
        String syslogFacility = attrs.get("syslogFacility");


        if(idlParser != null) {
            /** if we've parsed the IDL file, then all of the global setup has been done.
            *   We just need to verify this thread is connected to the OpenSRF network. */
            org.opensrf.Sys.bootstrapClient(configFile, configContext);
            return;
        }

        /** initialize the logging infrastructure */
        if("file".equals(logProto))
            Logger.init(Short.parseShort(logLevel), new FileLogger(logFile));

        if("syslog".equals(logProto)) 
            throw new ConfigException("syslog not yet implemented");

        /** connect to the opensrf network. */
        org.opensrf.Sys.bootstrapClient(configFile, configContext);

        /** Grab the IDL file setting */
        SettingsClient client = SettingsClient.instance();
        String idlFile = client.getString("/IDL");


        /** Parse the IDL if necessary */
        idlParser = new IDLParser(idlFile);
        idlParser.parse();
    }
}

