package org.opensrf;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.Random;
import java.util.Arrays;

import org.opensrf.util.*;


/**
 * Models an OpenSRF client session.
 */
public class ClientSession extends Session {

    /** The remote service to communicate with */
    private String service;
    /** OpenSRF domain */
    private String domain;
    /** Router name */
    private String router;

    /** 
     * original remote node.  The current remote node will change based 
     * on server responses.  This is used to reset the remote node to 
     * its original state.
     */
    private String origRemoteNode;
    /** The next request id */
    private int nextId;
    /** The requests this session has sent */
    private Map<Integer, Request> requests;

    /**
     * Creates a new client session.  Initializes the 
     * @param service The remove service.
     */
    public ClientSession(String service) throws ConfigException {
        this.service = service;

        /** generate the remote node string */
        domain = (String) Config.getFirst("/domains/domain");
        router = Config.getString("/router_name");
        setRemoteNode(router + "@" + domain + "/" + service);
        origRemoteNode = getRemoteNode();


        /** create a random thread */
        long time = new Date().getTime();
        Random rand = new Random(time);
        setThread(rand.nextInt()+""+rand.nextInt()+""+time);

        nextId = 0;
        requests = new HashMap<Integer, Request>();
        cacheSession();
    }

    /**
     * Creates a new request to send to our remote service.
     * @param method The method API name
     * @param params The list of method parameters
     * @return The request object.
     */
    public Request request(String method, List<Object> params) throws SessionException {
        return request(new Request(this, nextId++, method, params));
    }

    /**
     * Creates a new request to send to our remote service.
     * @param method The method API name
     * @param params The list of method parameters
     * @return The request object.
     */
    public Request request(String method, Object[] params) throws SessionException {
        return request(new Request(this, nextId++, method, Arrays.asList(params)));
    }


    /**
     * Creates a new request to send to our remote service.
     * @param method The method API name
     * @return The request object.
     */
    public Request request(String method) throws SessionException {
        return request(new Request(this, nextId++, method));
    }


    private Request request(Request req) throws SessionException {
        if(getConnectState() != ConnectState.CONNECTED)
            resetRemoteId();
        requests.put(new Integer(req.getId()), req);
        req.send();
        return req;
    }


    /**
     * Resets the remoteNode to its original state.
     */
    public void resetRemoteId() {
        setRemoteNode(origRemoteNode);
    }


    /**
     * Pushes a response onto the result queue of the appropriate request.
     * @param msg The received RESULT Message
     */
    public void pushResponse(Message msg) {

        Request req = requests.get(new Integer(msg.getId()));
        if(req == null) {
            /** LOG that we've received a result to a non-existant request */
            return;
        }
        OSRFObject payload = (OSRFObject) msg.get("payload");

        /** build a result and push it onto the request's result queue */
        req.pushResponse(
            new Result( 
                payload.getString("status"), 
                payload.getInt("statusCode"),
                payload.get("content")
            )
        );
    }

    /**
     * Removes a request for this session's request set
     */
    public void cleanupRequest(int reqId) {
        requests.remove(new Integer(reqId));
    }
}

