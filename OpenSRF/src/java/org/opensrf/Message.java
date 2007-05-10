package org.opensrf;


public class Message {

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
}


