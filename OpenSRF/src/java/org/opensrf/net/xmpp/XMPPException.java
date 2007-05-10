package org.opensrf.net.xmpp;

/**
 * Used for XMPP stream/authentication errors
 */
public class XMPPException extends Exception {
    public XMPPException(String info) {
        super(info);
    }
}
