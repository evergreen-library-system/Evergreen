package org.opensrf;
import org.opensrf.util.JSON;
import org.opensrf.net.xmpp.*;

public abstract class Session {

    /** Represents the different connection states for a session */
    public enum ConnectState {
        DISCONNECTED,
        CONNECTING,
        CONNECTED
    };

    /** the current connection state */
    private ConnectState connectState;

    /** The (jabber) address of the remote party we are communicating with */
    private String remoteNode;

    /** 
     * The thread is used to link messages to a given session. 
     * In other words, each session has a unique thread, and all messages 
     * in that session will carry this thread around as an indicator.
     */
    private String thread;

    public Session() {
        connectState = ConnectState.DISCONNECTED;
    }
    
    /**
     * Sends a Message to our remoteNode.
     */
    public void send(Message omsg) throws XMPPException {

        /** construct the XMPP message */
        XMPPMessage xmsg = new XMPPMessage();
        xmsg.setTo(remoteNode);
        xmsg.setThread(thread);
        xmsg.setBody(JSON.toJSON(omsg));
        XMPPSession ses = XMPPSession.getGlobalSession();

        try {
            XMPPSession.getGlobalSession().send(xmsg);
        } catch(XMPPException e) {
            /* XXX log */
            connectState = ConnectState.DISCONNECTED;
        }
    }
}
