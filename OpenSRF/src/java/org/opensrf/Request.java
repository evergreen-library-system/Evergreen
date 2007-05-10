package org.opensrf;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.List;
import org.opensrf.net.xmpp.XMPPException;

public class Request {
    
    private ClientSession session;
    private Method method;
    private int id;
    private Queue<Result> resultQueue;
    private boolean resetTimeout;
    private boolean complete;

    public Request(ClientSession ses, int id, Method method) {
        this.session = ses;
        this.id = id;
        this.method = method;
        resultQueue = new ConcurrentLinkedQueue<Result>();
        complete = false;
        resetTimeout = false;
    }

    public Request(ClientSession ses, int id, String methodName, List<Object> params) {
        this(ses, id, new Method(methodName, params));
    }

    public void send() throws XMPPException {
        session.send(new Message(id, Message.Type.REQUEST, method));
    }
}
