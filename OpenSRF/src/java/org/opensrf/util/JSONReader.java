package org.opensrf.util;

import java.io.*;
import java.util.*;

import org.json.JSONTokener;
import org.json.JSONObject;
import org.json.JSONArray;


/**
 * JSON utilities.
 */
public class JSONReader {

    /** Special OpenSRF serializable object netClass key */
    public static final String JSON_CLASS_KEY = "__c";

    /** Special OpenSRF serializable object payload key */
    public static final String JSON_PAYLOAD_KEY = "__p";

    private String json;

    public JSONReader(String json) {
        this.json = json;
    }

    /**
     * Parses JSON and creates an object.
     * @param json The JSON string to parse
     * @return The resulting object which may be a List, 
     * Map, Number, String, Boolean, or null
     */
    public Object read() throws JSONException {
        JSONTokener tk = new JSONTokener(json);
        try {
            return readSubObject(tk.nextValue());
        } catch(org.json.JSONException e) {
            throw new JSONException(e.toString());
        }
    }

    public List<?> readArray() throws JSONException {
        Object o = read();
        try {
            return (List<?>) o;
        } catch(Exception e) {
            throw new JSONException("readArray(): JSON cast exception");
        }
    }

    public Map<?,?> readObject() throws JSONException {
        Object o = read();
        try {
            return (Map<?,?>) o;
        } catch(Exception e) {
            throw new JSONException("readObject(): JSON cast exception");
        }
    }


    private Object readSubObject(Object obj) throws JSONException {

        if( obj == null || 
            obj instanceof String || 
            obj instanceof Number ||
            obj instanceof Boolean)
                return obj;

        try {

            if( obj instanceof JSONObject ) {

                /* read objects */
                String key;
                JSONObject jobj = (JSONObject) obj;
                Map<String, Object> map = new HashMap<String, Object>();

                for( Iterator e = jobj.keys(); e.hasNext(); ) {
                    key = (String) e.next();

                    /* we encoutered the special class key */
                    if( JSON_CLASS_KEY.equals(key) ) 
                        return buildRegisteredObject(
                            (String) jobj.get(key), jobj.get(JSON_PAYLOAD_KEY));

                    /* we encountered the data key */
                    if( JSON_PAYLOAD_KEY.equals(key) ) 
                        return buildRegisteredObject(
                            (String) jobj.get(JSON_CLASS_KEY), jobj.get(key));

                    map.put(key, readSubObject(jobj.get(key)));
                }
                return map;
            } 
            
            if ( obj instanceof JSONArray ) {

                JSONArray jarr = (JSONArray) obj;
                int length = jarr.length();
                List<Object> list = new ArrayList<Object>(length);

                for( int i = 0; i < length; i++ ) 
                    list.add(readSubObject(jarr.get(i)));   
                return list;
                
            }

        } catch(org.json.JSONException e) {

            throw new JSONException(e.toString());
        }

        return null;
    }



    /**
     * Builds an OSRFObject map registered OSRFHash object based on the JSON object data.
     * @param netClass The network class hint for this object.
     * @param paylaod The actual object on the wire.
     */
    private OSRFObject buildRegisteredObject(
        String netClass, Object payload) throws JSONException {

        OSRFRegistry registry = OSRFRegistry.getRegistry(netClass);
        OSRFObject obj = new OSRFObject(registry);

        try {
            if( payload instanceof JSONArray ) {
                JSONArray jarr = (JSONArray) payload;

                /* for each array item, instert the item into the hash.  the hash 
                 * key is found by extracting the fields array from the registered 
                 * object at the current array index */
                String fields[] = registry.getFields();
                for( int i = 0; i < jarr.length(); i++ ) {
                    obj.put(fields[i], readSubObject(jarr.get(i)));   
                }

            } else if( payload instanceof JSONObject ) {

                /* since this is a hash, simply copy the data over */
                JSONObject jobj = (JSONObject) payload;
                String key;
                for( Iterator e = jobj.keys(); e.hasNext(); ) {
                    key = (String) e.next();
                    obj.put(key, readSubObject(jobj.get(key)));
                }
            }

        } catch(org.json.JSONException e) {
            throw new JSONException(e.toString());
        }

        return obj;
    }
}



