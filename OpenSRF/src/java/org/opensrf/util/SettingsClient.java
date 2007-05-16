package org.opensrf.util;
import org.opensrf.*;
import java.util.Map;

/**
 * Connects to the OpenSRF Settings server to fetch the settings config.  
 * Provides a Config interface for fetching settings via path
 */
public class SettingsClient extends Config {

    /** Singleton SettingsClient instance */
    private static SettingsClient client = new SettingsClient();

    public SettingsClient() {
        super("");
    }

    /**
     * @return The global settings client instance 
     */
    public static SettingsClient instance() throws ConfigException {
        if(client.getConfigObject() == null) 
            client.fetchConfig();
        return client;
    }

    /**
     * Fetches the settings object from the settings server
     */
    private void fetchConfig() throws ConfigException {

        ClientSession ses = new ClientSession("opensrf.settings");
        try {

            Request req = ses.request(
                "opensrf.settings.host_config.get", 
                new String[]{(String)Config.global().getFirst("/domains/domain")});
    
            Result res = req.recv(12000);
            if(res == null) {
                /** throw exception */
            }
            setConfigObject((Map) res.getContent());

        } catch(Exception e) {
            throw new ConfigException("Error fetching settings config", e);

        } finally {
            ses.cleanup();
        }
    }
}

