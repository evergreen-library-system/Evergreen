package org.opensrf.net.xmpp;

/**
 * Used for XMPP stream/authentication errors
 */
public class XMPPException extends Exception {
    private String info;

    /**
     * @param info Runtime exception information.
     */
    public XMPPException(String info) {
        this.info = info;
    }
    public String toString() {
        return this.info;
    }
}
