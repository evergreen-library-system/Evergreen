package org.opensrf;
import org.opensrf.util.*;


/**
 * Models a single result from a method request.
 */
public class Result {

    /** Method result content */
    private Object content;
    /** Name of the status */
    private String status;
    /** Status code number */
    private int statusCode;


    /** Register this object */
    private static OSRFRegistry registry = 
        OSRFRegistry.registerObject(
            "osrfResult", 
            OSRFRegistry.WireProtocol.HASH, 
            new String[] {"status", "statusCode", "content"});


    public Result(String status, int statusCode, Object content) {
        this.status = status;
        this.statusCode = statusCode;
        this.content = content;
    }
    
    /**
     * Get status.
     * @return status as String.
     */
    public String getStatus() {
        return status;
    }
    
    /**
     * Set status.
     * @param status the value to set.
     */
    public void setStatus(String status) {
        this.status = status;
    }
    
    /**
     * Get statusCode.
     * @return statusCode as int.
     */
    public int getStatusCode() {
        return statusCode;
    }
    
    /**
     * Set statusCode.
     * @param statusCode the value to set.
     */
    public void setStatusCode(int statusCode) {
        this.statusCode = statusCode;
    }
    
    /**
     * Get content.
     * @return content as Object.
     */
    public Object getContent() {
        return content;
    }
    
    /**
     * Set content.
     * @param content the value to set.
     */
    public void setContent(Object content) {
        this.content = content;
    }

    /**
     * Implements the generic get() API required by OSRFSerializable
     */
    public Object get(String field) {
        if("status".equals(field))
            return getStatus();
        if("statusCode".equals(field))
            return getStatusCode();
        if("content".equals(field))
            return getContent();
        return null;
    }

    public OSRFRegistry getRegistry() {
        return registry;
    }

}

