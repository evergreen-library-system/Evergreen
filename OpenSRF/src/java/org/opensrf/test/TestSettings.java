package org.opensrf.test;
import org.opensrf.*;
import org.opensrf.util.*;

public class TestSettings {
    public static void main(String args[]) throws Exception {
        Sys.bootstrapClient(args[0], "/config/opensrf");
        SettingsClient client = SettingsClient.instance();
        //Object obj = client.get("/apps");
        //System.out.println(new JSONWriter(obj).write());
        String lang = client.getString("/apps/opensrf.settings/language");
        String impl = client.getString("/apps/opensrf.settings/implementation");
        System.out.println("opensrf.settings language = " + lang);
        System.out.println("opensrf.settings implementation = " + impl);
    }
}
