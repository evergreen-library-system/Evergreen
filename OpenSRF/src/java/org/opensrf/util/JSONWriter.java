package org.opensrf.util;

import java.io.*;
import java.util.*;


/**
 * JSONWriter
 */
public class JSONWriter {

    /** The object to serialize to JSON */
    private Object obj;

    public JSONWriter(Object obj) {
        this.obj = obj;
    }


    /**
     * @see write(Object, StringBuffer)
     */
    public String write() {
        StringBuffer sb = new StringBuffer();
        write(sb);
        return sb.toString();
    }



    /**
     * Encodes a java object to JSON.
     * Maps (HashMaps, etc.) are encoded as JSON objects.  
     * Iterable's (Lists, etc.) are encoded as JSON arrays
     */
    public void write(StringBuffer sb) {
        write(obj, sb);
    }

    public void write(Object obj, StringBuffer sb) {

        /** JSON null */
        if(obj == null) {
            sb.append("null");
            return;
        }

        /** JSON string */
        if(obj instanceof String) {
            sb.append('"');
            Utils.escape((String) obj, sb);
            sb.append('"');
            return;
        }

        /** JSON number */
        if(obj instanceof Number) {
            sb.append(obj.toString());
            return;
        }

        /** JSON array */
        if(obj instanceof Iterable) {
            encodeJSONArray((Iterable) obj, sb);
            return;
        }

        /** OpenSRF serializable objects */
        if(obj instanceof OSRFSerializable) {
            encodeOSRFSerializable((OSRFSerializable) obj, sb);
            return;
        }

        /** JSON object */
        if(obj instanceof Map) {
            encodeJSONObject((Map) obj, sb);
            return;
        }

        /** JSON boolean */
        if(obj instanceof Boolean) {
            sb.append((((Boolean) obj).booleanValue() ? "true" : "false"));
            return;
        }
    }


    /**
     * Encodes a List as a JSON array
     */
    private void encodeJSONArray(Iterable iterable, StringBuffer sb) {
        Iterator itr = iterable.iterator();
        sb.append("[");
        boolean some = false;

        while(itr.hasNext()) {
            some = true;
            write(itr.next(), sb);
            sb.append(',');
        }

        /* remove the trailing comma if the array has any items*/
        if(some) 
            sb.deleteCharAt(sb.length()-1); 
        sb.append("]");
    }


    /**
     * Encodes a Map as a JSON object
     */
    private void encodeJSONObject(Map map, StringBuffer sb) {
        Iterator itr = map.keySet().iterator();
        sb.append("{");
        Object key = null;

        while(itr.hasNext()) {
            key = itr.next();
            write(key, sb);
            sb.append(':');
            write(map.get(key), sb);
            sb.append(',');
        }

        /* remove the trailing comma if the object has any items*/
        if(key != null) 
            sb.deleteCharAt(sb.length()-1); 
        sb.append("}");
    }


    /**
     * Encodes a network-serializable OpenSRF object
     */
    private void encodeOSRFSerializable(OSRFSerializable obj, StringBuffer sb) {

        OSRFRegistry reg = obj.getRegistry();
        String[] fields = reg.getFields();
        Map<String, Object> map = new HashMap<String, Object>();
        map.put(JSONReader.JSON_CLASS_KEY, reg.getNetClass());

        if( reg.getWireProtocol() == OSRFRegistry.WireProtocol.ARRAY ) {

            List<Object> list = new ArrayList<Object>(fields.length);
            for(String s : fields)
                list.add(obj.get(s));
            map.put(JSONReader.JSON_PAYLOAD_KEY, list);

        } else {

            Map<String, Object> subMap = new HashMap<String, Object>();
            for(String s : fields)
                subMap.put(s, obj.get(s));
            map.put(JSONReader.JSON_PAYLOAD_KEY, subMap);
                
        }

        /** now serialize the encoded object */
        write(map, sb);
    }
}



