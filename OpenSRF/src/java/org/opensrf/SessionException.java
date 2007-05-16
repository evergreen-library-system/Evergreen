package org.opensrf;
/**
 * Used by sessions to indicate communication errors
 */
public class SessionException extends Exception {
    public SessionException(String info) {
        super(info);
    }
    public SessionException(String info, Throwable cause) {
        super(info, cause);
    }
}

