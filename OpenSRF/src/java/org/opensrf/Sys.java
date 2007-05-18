package org.opensrf;

import org.opensrf.util.*;
import org.opensrf.net.xmpp.*;


public class Sys {

    /**
     * Connects to the OpenSRF network so that client sessions may communicate.
     * @param configFile The OpenSRF config file 
     * @param configContext Where in the XML document the config chunk lives.  This
     * allows an OpenSRF client config chunk to live in XML files where other config
     * information lives.
     */
    public static void bootstrapClient(String configFile, String configContext) 
            throws ConfigException, SessionException  {

        /** create the config parser */
        Config config = new Config(configContext);
        config.parse(configFile);
        Config.setConfig(config); /* set this as the global config */

        /** Collect the network connection info from the config */
        String username = config.getString("/username");
        String passwd = config.getString("/passwd");
        String host = (String) config.getFirst("/domains/domain");
        int port = config.getInt("/port");

        try {
            /** Connect to the Jabber network */
            XMPPSession xses = new XMPPSession(host, port);
            xses.connect(username, passwd, "test-java"); /* XXX */
            XMPPSession.setGlobalSession(xses);
        } catch(XMPPException e) {
            throw new SessionException("Unable to bootstrap client", e);
        }
    }

    /**
     * Shuts down the connection to the opensrf network
     */
    public static void shutdown() {
        XMPPSession.getGlobalSession().disconnect();
    }
}

