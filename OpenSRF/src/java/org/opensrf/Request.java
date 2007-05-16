package org.opensrf;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.List;
import java.util.Date;
import org.opensrf.net.xmpp.XMPPException;

public class Request {
    
    /** This request's controlling session */
    private ClientSession session;
    /** The method */
    private Method method;
    /** The ID of this request */
    private int id;
    /** Queue of Results */
    private Queue<Result> resultQueue;
    /** If true, the receive timeout for this request should be reset */
    private boolean resetTimeout;

    /** If true, the server has indicated that this request is complete. */
    private boolean complete;

    /**
     * @param ses The controlling session for this request.
     * @param id This request's ID.
     * @param method The requested method.
     */
    public Request(ClientSession ses, int id, Method method) {
        this.session = ses;
        this.id = id;
        this.method = method;
        resultQueue = new ConcurrentLinkedQueue<Result>();
        complete = false;
        resetTimeout = false;
    }

    /**
     * @param ses The controlling session for this request.
     * @param id This request's ID.
     * @param methodName The requested method's API name.
     */
    public Request(ClientSession ses, int id, String methodName) {
        this(ses, id, new Method(methodName));
    }

    /**
     * @param ses The controlling session for this request.
     * @param id This request's ID.
     * @param methodName The requested method's API name.
     * @param params The list of request params
     */
    public Request(ClientSession ses, int id, String methodName, List<Object> params) {
        this(ses, id, new Method(methodName, params));
    }

    /**
     * Sends the request to the server.
     */
    public void send() throws SessionException {
        session.send(new Message(id, Message.REQUEST, method));
    }

    /**
     * Receives the next result for this request.  This method
     * will wait up to the specified number of milliseconds for 
     * a response. 
     * @param millis Number of milliseconds to wait for a result.  If
     * negative, this method will wait indefinitely.
     * @return The result or null if none arrives in time
     */
    public Result recv(long millis) throws SessionException {

        Result result = null;

        if(millis < 0 && !complete) {
            /** wait potentially forever for a result to arrive */
            session.waitForMessage(millis);
            if((result = resultQueue.poll()) != null)
                return result;

        } else {

            while(millis >= 0 && !complete) {

                /** wait up to millis milliseconds for a result.  waitForMessage() 
                 * will return if a response to any request arrives, so we keep track
                 * of how long we've been waiting in total for a response to 
                 * this request
                 */
                long start = new Date().getTime();
                session.waitForMessage(millis);
                millis -= new Date().getTime() - start;
                if((result = resultQueue.poll()) != null)
                    return result;
            }
        }

        return null;
    }

    /**
     * Pushes a result onto the result queue 
     * @param result The result to push
     */
    public void pushResponse(Result result) {
        resultQueue.offer(result);
    }

    /**
     * @return This request's ID
     */
    public int getId() {
        return id;
    }

    /**
     * Removes this request from the controlling session's request set
     */
    public void cleanup() {
        session.cleanupRequest(id);
    }

    /** Sets this request as complete */
    public void setComplete() {
        complete = true;
    }
}
