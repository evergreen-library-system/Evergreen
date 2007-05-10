package org.opensrf.test;

import org.opensrf.util.JSON;
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

        System.out.println(JSON.toJSON(map));
    }
}
