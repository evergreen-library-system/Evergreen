package org.opensrf.util;

import java.util.Map;
import java.util.HashMap;


/**
 * Manages the registration of OpenSRF network-serializable objects.  
 * A serializable object has a class "hint" (called netClass within) which
 * describes the type of object.  Each object also has a set of field names
 * for accessing/mutating object properties.  Finally, objects have a 
 * serialization wire protocol.  Currently supported protocols are HASH
 * and ARRAY.
 */
public class OSRFRegistry {


    /**
     * Global collection of registered net objects.  
     * Maps netClass names to registries.
     */
    private static HashMap<String, OSRFRegistry> 
        registry = new HashMap<String, OSRFRegistry>();


    /** Serialization types for registered objects */
    public enum WireProtocol {
        ARRAY, HASH
    };


    /** Array of field names for this registered object */
    String fields[];
    /** The wire protocol for this object */
    WireProtocol wireProtocol;
    /** The network class for this object */
    String netClass;

    /**
     * Returns the array of field names
     */
    public String[] getFields() {
        return this.fields;
    }


    /**
     * Registers a new object.
     * @param netClass The net class for this object
     * @param wireProtocol The object's wire protocol
     * @param fields An array of field names.  For objects whose
     * wire protocol is ARRAY, the positions of the field names 
     * will be used as the array indices for the fields at serialization time
     */
    public static OSRFRegistry registerObject(String netClass, WireProtocol wireProtocol, String fields[]) {
        OSRFRegistry r = new OSRFRegistry(netClass, wireProtocol, fields);
        registry.put(netClass, r);
        return r;
    }

    /**
     * Returns the registry for the given netclass
     * @param netClass The network class to lookup
     */
    public static OSRFRegistry getRegistry(String netClass) {
        if( netClass == null ) return null;
        return (OSRFRegistry) registry.get(netClass);
    }


    /**
     * @param field The name of the field to lookup
     * @return the index into the fields array of the given field name.
     */
    public int getFieldIndex(String field) {
        for( int i = 0; i < fields.length; i++ )
            if( fields[i].equals(field) ) 
                return i;
        return -1;
    }

    /** Returns the wire protocol of this object */
    public WireProtocol getWireProtocol() {
        return this.wireProtocol;
    }

    /** Returns the netClass ("hint") of this object */
    public String getNetClass() {
        return this.netClass;
    }

    /**
     * Creates a new registry object.
     * @param netClass The network class/hint
     * @param wireProtocol The wire protocol
     * @param fields The array of field names.  For array-based objects,
     * the fields array must be sorted in accordance with the sorting
     * of the objects in the array.
     */ 
    public OSRFRegistry(String netClass, WireProtocol wireProtocol, String fields[]) {
        this.netClass = netClass;
        this.wireProtocol = wireProtocol;
        this.fields = fields;
    }
}


