package org.opensrf.test;

import org.opensrf.*;
import org.opensrf.util.*;
import java.util.*;

public class TestJSON {

    public static void main(String args[]) {
        
        Map<String,Object> map = new HashMap<String,Object>();
        map.put("key1", "value1");
        map.put("key2", "value2");
        map.put("key3", "value3");
        map.put("key4", "athe\u0301s");
        map.put("key5", null);

        List<Object> list = new ArrayList<Object>(16);
        list.add(new Integer(1));
        list.add(new Boolean(true));
        list.add("WATER");
        list.add(null);
        map.put("key6", list);

        System.out.println(JSON.toJSON(map) + "\n");

        String[] fields = {"isnew", "name", "shortname", "ill_address"};
        OSRFRegistry.registerObject("aou", OSRFRegistry.WireProtocol.ARRAY, fields);

        OSRFObject obj = new OSRFObject(OSRFRegistry.getRegistry("aou"));
        obj.put("name", "athens clarke county");
        obj.put("ill_address", new Integer(1));
        obj.put("shortname", "ARL-ATH");

        map.put("key7", obj);
        list.add(obj);
        System.out.println(JSON.toJSON(map) + "\n");


        Message m = new Message(1, Message.Type.REQUEST);
        Method method = new Method("opensrf.settings.host_config.get");
        method.addParam("app07.dev.gapines.org");
        m.setPayload(method);

        System.out.println(JSON.toJSON(m) + "\n");
    }
}
