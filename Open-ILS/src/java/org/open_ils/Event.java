package org.open_ils;

import java.util.Map;
import java.util.HashMap;

public class Event extends HashMap<String, Object> {

    public Event() {
    }

    public Event(Map<String, Object> map) {
        super(map);
    }

    public static Event parseEvent(Object map) {
        if( map != null && map instanceof Map) {
            Map m = (Map) map;
            if( m.containsKey("ilsevent") && m.containsKey("textcode")) 
                return new Event(m);
        }
        
        return null;
    }

    public String getTextCode() {
        return (String) get("textcode");
    }

    public int getCode() {
        return Integer.parseInt((String) get("ilsevent"));
    }
}

