package org.opensrf.util;

/**
 * Thrown by the Config module when a user requests a configuration
 * item that does not exist
 */
public class ConfigException extends Exception {
    public ConfigException(String info) {
        super(info);
    }
}
