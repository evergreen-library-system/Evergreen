package org.opensrf;
import org.opensrf.util.*;


public class Message implements OSRFSerializable {

    public static final String REQUEST = "REQUEST";
    public static final String STATUS = "STATUS";
    public static final String RESULT = "RESULT";
    public static final String CONNECT = "CONNECT";
    public static final String DISCONNECT = "DISCONNECT";

    /** Message ID.  This number is used to relate requests to responses */
    private int id;
    /** String of message. */
    private String type;
    /** message payload */
    private Object payload;

    /** Go ahead and register the Message object */
    private static OSRFRegistry registry = 
        OSRFRegistry.registerObject(
            "osrfMessage", 
            OSRFRegistry.WireProtocol.HASH, 
            new String[] {"threadTrace", "type", "payload"});

    /**
     * @param id This message's ID
     * @param type The type of message
     */
    public Message(int id, String type) {
        setId(id);
        setString(type);
    }
    public Message(int id, String type, Object payload) {
        this(id, type);
        setPayload(payload);
    }


    public int getId() {
        return id;
    }   
    public String getType() {
        return type;
    }
    public Object getPayload() {
        return payload;
    }
    public void setId(int id) {
        this.id = id;
    }
    public void setString(String type) {
        this.type = type;
    }
    public void setPayload(Object p) {
        payload = p;
    }

    /**
     * Implements the generic get() API required by OSRFSerializable
     */
    public Object get(String field) {
        if("threadTrace".equals(field))
            return getId();
        if("type".equals(field))
            return getType().toString();
        if("payload".equals(field))
            return getPayload();
        return null;
    }

    public OSRFRegistry getRegistry() {
        return registry;
    }
}


