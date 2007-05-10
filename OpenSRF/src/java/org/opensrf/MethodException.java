package org.opensrf;

/**
 * Thrown when the server responds with a method exception.
 */
public class MethodException extends Exception {
    public MethodException(String info) {
        super(info);
    }
}

