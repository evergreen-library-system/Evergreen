package org.opensrf;
import java.util.List;
import java.util.ArrayList;
import org.opensrf.util.*;


public class Method extends OSRFObject {

    /** The method API name */
    private String name;
    /** The ordered list of method params */
    private List<Object> params;

    /** Create a registry for the osrfMethod object */
    private static OSRFRegistry registry = 
        OSRFRegistry.registerObject(
            "osrfMethod", 
            OSRFRegistry.WireProtocol.HASH, 
            new String[] {"method", "params"});

    /**
     * @param name The method API name 
     */
    public Method(String name) {
        this.name = name;
        this.params = new ArrayList<Object>(8);
    }

    /**
     * @param name The method API name
     * @param params The ordered list of params
     */
    public Method(String name, List<Object> params) {
        this.name = name;
        this.params = params;
    }

    /**
     * @return The method API name
     */
    public String getName() {
        return name;
    }
    /**
     * @return The ordered list of params
     */
    public List<Object> getParams() {
       return params; 
    }

    /**
     * Pushes a new param object onto the set of params 
     * @param p The new param to add to the method.
     */
    public void addParam(Object p) {
        this.params.add(p);
    }

    /**
     * Implements the generic get() API required by OSRFSerializable
     */
    public Object get(String field) {
        if("method".equals(field))
            return getName();
        if("params".equals(field))
            return getParams();
        return null;
    }

    /**
     * @return The osrfMethod registry.
     */
    public OSRFRegistry getRegistry() {
        return registry;
    }

}

