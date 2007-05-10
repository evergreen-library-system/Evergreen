package org.opensrf;
import java.util.List;
import java.util.ArrayList;
import org.opensrf.util.*;


public class Method implements OSRFSerializable {

    private String name;
    private List<Object> params;

    /** Register this object */
    private static OSRFRegistry registry = 
        OSRFRegistry.registerObject(
            "osrfMethod", 
            OSRFRegistry.WireProtocol.HASH, 
            new String[] {"method", "params"});


    public Method(String name) {
        this.name = name;
        this.params = new ArrayList<Object>(8);
    }

    public Method(String name, List<Object> params) {
        this.name = name;
        this.params = params;
    }

    public String getName() {
        return name;
    }
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

    public OSRFRegistry getRegistry() {
        return registry;
    }

}

