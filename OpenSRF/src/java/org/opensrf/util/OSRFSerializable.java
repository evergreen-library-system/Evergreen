package org.opensrf.util;

/**
 * All network-serializable OpenSRF object must implement this interface.
 */
public interface OSRFSerializable {

    /**
     * Returns the object registry object for the implementing class.
     */
    public abstract OSRFRegistry getRegistry();

    public abstract Object get(String field);
}


