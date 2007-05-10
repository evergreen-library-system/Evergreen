package org.opensrf;


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
}

