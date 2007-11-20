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

    /**
     * Initializes the connection to the OpenSRF network and parses the IDL file.
     * @param attrs A map of configuration attributes.  Options include:<br/>
     * <ul>
     * <li>configFile - The OpenSRF core config file</li>
     * <li>configContext - The path to the config chunk in the config XML, typically "opensrf"</li>
     * <li>logProtocol - Currently supported option is "file".</li>
     * <li>logLevel - The log level.  Options are 1,2,3, or 4 (error, warn, info, debug)</li>
     * <li>syslogFacility - For future use, when syslog is a supported log option</li>
     * <li>idlFile - The path to the IDL file.  May be relative or absolute.  If this option is 
     * not provided, the system will ask the OpenSRF Settings server for the IDL file path.</li>
     * </ul>
     */
    public static void init(Map<String, String> attrs) throws ConfigException, SessionException, IOException, IDLException {

        String configFile = attrs.get("configFile");
        String configContext = attrs.get("configContext");
        String logProto = attrs.get("logProtocol");
        String logFile = attrs.get("logFile");
        String logLevel = attrs.get("logLevel");
        String syslogFacility = attrs.get("syslogFacility");
        String idlFile = attrs.get("idlFile");


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

        /** Grab the IDL file setting if not explicitly provided */
        if(idlFile == null) {
            SettingsClient client = SettingsClient.instance();
            idlFile = client.getString("/IDL");
        }

        /** Parse the IDL if necessary */
        idlParser = new IDLParser(idlFile);
        idlParser.parse();
    }
}

