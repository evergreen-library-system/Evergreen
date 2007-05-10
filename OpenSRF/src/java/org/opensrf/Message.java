package org.opensrf;
import org.opensrf.util.*;


public class Message implements OSRFSerializable {

    /** Message types */
    public enum Type {
        REQUEST,
        STATUS,
        RESULT,
        CONNECT,
        DISCONNECT,
    };

    /** Message ID.  This number is used to relate requests to responses */
    private int id;
    /** Type of message. */
    private Type type;
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
    public Message(int id, Type type) {
        setId(id);
        setType(type);
    }

    public int getId() {
        return id;
    }   
    public Type getType() {
        return type;
    }
    public Object getPayload() {
        return payload;
    }
    public void setId(int id) {
        this.id = id;
    }
    public void setType(Type type) {
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


