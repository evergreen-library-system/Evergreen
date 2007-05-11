package org.opensrf.test;
import org.opensrf.*;
import org.opensrf.util.*;
import org.opensrf.net.xmpp.*;
import java.io.PrintStream;
import java.util.Map;


public class TestClient {
    public static void main(String args[]) throws Exception {
        
        PrintStream out = System.out;

        try {

            /** setup the config parser */
            String configFile = args[0];
            Config config = new Config("/config/opensrf");
            config.parse(configFile);
            Config.setConfig(config);

            /** Connect to jabber */
            String username = Config.getString("/username");
            String passwd = Config.getString("/passwd");
            String host = (String) Config.getFirst("/domains/domain");
            int port = Config.getInt("/port");
            XMPPSession xses = new XMPPSession(host, port);
            xses.connect(username, passwd, "test-java-client");
            XMPPSession.setGlobalSession(xses);
    
            /** build the client session and send the request */
            ClientSession session = new ClientSession("opensrf.settings");
            Request request = session.request(
                "opensrf.settings.host_config.get", 
                new String[] {args[1]}
            );

            Result result = request.recv(10000);
            if(result == null) {
                out.println("no result");
                return;
            }

            out.println("status = " + result.getStatus());
            out.println("status code = " + result.getStatusCode());

            out.println("setting config memcache server(s) = " +
                new JSONWriter(
                    Utils.findPath( (Map) result.getContent(), 
                    "/cache/global/servers/server")
                ).write());


        } catch(ArrayIndexOutOfBoundsException e) {
            out.println("usage: org.opensrf.test.TestClient <osrfConfigFile> <domain>");
            return;
        }
    }
}



