package org.opensrf;
import org.opensrf.util.JSONWriter;
import org.opensrf.net.xmpp.*;
import java.util.Map;
import java.util.HashMap;

public abstract class Session {

    /** Represents the different connection states for a session */
    public enum ConnectState {
        DISCONNECTED,
        CONNECTING,
        CONNECTED
    };

    /** local cache of existing sessions */
    private static Map<String, Session> 
        sessionCache = new HashMap<String, Session>();

    /** the current connection state */
    private ConnectState connectState;

    /** The (jabber) address of the remote party we are communicating with */
    private String remoteNode;

    /** 
     * The thread is used to link messages to a given session. 
     * In other words, each session has a unique thread, and all messages 
     * in that session will carry this thread around as an indicator.
     */
    protected String thread;

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
        xmsg.setBody(new JSONWriter(omsg).write());
        XMPPSession ses = XMPPSession.getGlobalSession();

        try {
            XMPPSession.getGlobalSession().send(xmsg);
        } catch(XMPPException e) {
            /* XXX log.. what else? */
            connectState = ConnectState.DISCONNECTED;
        }
    }

    /**
     * Waits for a message to arrive over the network and passes
     * all received messages to the stack for processing
     * @param millis The number of milliseconds to wait for a message to arrive
     */
    public static void waitForMessage(long millis) {
        try {
            Stack.processXMPPMessage(
                XMPPSession.getGlobalSession().recv(millis));
        } catch(XMPPException e) {
            /* XXX log.. what else? */
        }
    }

    /**
     * Removes this session from the session cache.
     */
    public void cleanup() {
        sessionCache.remove(thread);
    }

    /**
     * Searches for the cached session with the given thread.
     * @param thread The session thread.
     * @return The found session or null.
     */
    public static Session findCachedSession(String thread) {
        return sessionCache.get(thread);
    }

    protected void cacheSession() {
        sessionCache.put(thread, this);
    }

    public void setRemoteNode(String nodeName) {
        remoteNode = nodeName;
    }
    public String getRemoteNode() {
        return remoteNode;
    }
}
