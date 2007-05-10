package org.opensrf;
import java.util.List;
import java.util.ArrayList;


public class Method {

    private String name;
    private List<Object> params;

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
    public void pushParam(Object p) {
        this.params.add(p);
    }
}

