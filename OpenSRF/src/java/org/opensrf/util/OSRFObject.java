package org.opensrf.util;

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
     * Gets the object at the given fields.  We override this here
     * as part of the contract with OSRFSerializable
     * @param field the field name to get.
     * @return The object contained at the given field.
     */
    public Object get(String field) {
        return super.get(field);
    }
}
