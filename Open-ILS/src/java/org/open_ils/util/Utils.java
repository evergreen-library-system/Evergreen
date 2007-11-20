package org.open_ils.util;
import org.open_ils.*;
import org.opensrf.*;
import org.opensrf.util.*;
import java.util.Map;
import java.util.HashMap;
import java.security.MessageDigest;

public class Utils {
    
    /**
     * Logs in.
     * @param params Login arguments, which may consist of<br/>
     * username<br/>
     * barcode - if username is provided, barcode will be ignored<br/>
     * password<br/>
     * workstation - name of the workstation where the login is occuring<br/>
     * type - type of login, currently "opac", "staff", and "temp"<br/>
     * org - optional org ID to provide login context when no workstation is used.
     * @return An Event object.  On success, the event 'payload' will contain
     * 'authtoken' and 'authtime' fields, which represent the session key and 
     * session inactivity timeout, respectively.
     */
    public static Event login(Map params) throws MethodException {

        Map<String, String> initMap = new HashMap<String, String>();
        String init = (params.get("username") != null) ? 
            params.get("username").toString() : params.get("barcode").toString();

        Object resp = ClientSession.atomicRequest(
            "open-ils.auth",
            "open-ils.auth.authenticate.init", new Object [] {init});

        /** see if the server responded with some type of unexpected event */
        Event evt = Event.parseEvent(resp);
        if(evt != null) return evt;

        params.put("password", md5Hex(resp + md5Hex(params.get("password").toString())));

        resp = ClientSession.atomicRequest(
            "open-ils.auth",
            "open-ils.auth.authenticate.complete", new Object[]{params});

        return Event.parseEvent(resp);
    }


    /**
     * Generates the hex md5sum of a string.
     * @param s The string to md5sum
     * @return The 32-character hex md5sum
     */
    public static String md5Hex(String s) {
        StringBuffer sb = new StringBuffer();
        MessageDigest md;
        try {
            md = MessageDigest.getInstance("MD5");
        } catch(Exception e) {
            return null;
        }

        md.update(s.getBytes());
        byte[] digest = md.digest();
        for (int i = 0; i < digest.length; i++) {
            int b = digest[i] & 0xff;
            String hex = Integer.toHexString(b);
            if (hex.length() == 1) sb.append("0");
            sb.append(hex);
        }
        return sb.toString();
    }
}



