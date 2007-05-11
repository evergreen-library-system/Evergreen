package org.opensrf.util;

import java.util.Map;
import java.util.HashMap;


/**
 * Generic OpenSRF network-serializable object.  This allows
 * access to object fields.  
 */
public class OSRFObject extends HashMap<String, Object> implements OSRFSerializable {
    
    /** This objects registry */
    private OSRFRegistry registry;

    public OSRFObject() {
    }


    /*
    public OSRFObject(String netClass, Map map) {
        super(map);
        registry = OSRFRegistry.getRegistry(netClass);
    }
    */

    /**
     * Creates a new object with the provided registry
     */
    public OSRFObject(OSRFRegistry reg) {
        this();
        registry = reg;
    }


    /**
     * @return This object's registry
     */
    public OSRFRegistry getRegistry() {
        return registry;
    }

    /**
     * Implement get() to fulfill our contract with OSRFSerializable
     */
    public Object get(String field) {
        return super.get(field);
    }

    public String getString(String field) {
        return (String) get(field);
    }

    public int getInt(String field) {
        return ((Integer) get(field)).intValue();
    }
}
