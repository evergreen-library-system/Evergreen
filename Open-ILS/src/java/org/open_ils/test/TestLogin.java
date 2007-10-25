package org.open_ils.test;
import org.open_ils.util.Utils;
import org.open_ils.Event;
import org.opensrf.*;
import java.util.Map;
import java.util.HashMap;


public class TestLogin {
    public static void main(String args[]) {
        try {

            if(args.length < 3) {
                System.err.println("usage: java org.open_ils.test.TestLogin <opensrf_config> <username> <password>");
                return;
            }

            Sys.bootstrapClient(args[0], "/config/opensrf");
            Map<String,String> params = new HashMap<String,String>();
            params.put("username", args[1]);
            params.put("password", args[2]);
            Event evt = Utils.login(params);
            System.out.println(evt);
        } catch(Exception e) {
            System.err.println(e);
        }
    }
}

