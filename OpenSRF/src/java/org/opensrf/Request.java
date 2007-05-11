package org.opensrf;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.List;
import java.util.Date;
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

    public Request(ClientSession ses, int id, String methodName) {
        this(ses, id, new Method(methodName));
    }

    public Request(ClientSession ses, int id, String methodName, List<Object> params) {
        this(ses, id, new Method(methodName, params));
    }

    public void send() throws SessionException {
        session.send(new Message(id, Message.REQUEST, method));
    }

    public Result recv(long millis) throws SessionException {

        Result result = null;

        if(millis < 0) {
            session.waitForMessage(millis);
            if((result = resultQueue.poll()) != null)
                return result;

        } else {

            while(millis >= 0) {
                long start = new Date().getTime();
                session.waitForMessage(millis);
                millis -= new Date().getTime() - start;
                if((result = resultQueue.poll()) != null)
                    return result;
            }
        }

        return null;
    }

    public void pushResponse(Result result) {
        resultQueue.offer(result);
    }

    /**
     * @return This request's ID
     */
    public int getId() {
        return id;
    }
}
