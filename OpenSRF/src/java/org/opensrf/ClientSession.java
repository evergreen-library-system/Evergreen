package org.opensrf;
import java.util.Date;
import java.util.List;
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
    private String domain;
    private String router;
    private String origRemoteNode;
    private int nextId;
    private List<Request> requests;

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


        /* create a random thread */
        long time = new Date().getTime();
        Random rand = new Random(time);
        setThread(rand.nextInt()+""+rand.nextInt()+""+time);

        requests = new ArrayList<Request>();
        nextId = 0;
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


    public Request request(Request req) throws SessionException {
        if(getConnectState() != ConnectState.CONNECTED)
            resetRemoteId();
        //requests.set(req.getId(), req); 
        requests.add(req); 
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
     * Pushes a response onto the queue of the appropriate request.
     * @param msg The the received RESULT Message whose payload 
     * contains a Result object.
     */
    public void pushResponse(Message msg) {

        Request req;

        try {
           req = requests.get(msg.getId());
        } catch(IndexOutOfBoundsException e) {
            /** LOG that an unexpected response arrived */
            return;
        }

        OSRFObject payload = (OSRFObject) msg.get("payload");

        req.pushResponse(
            new Result( 
                payload.getString("status"), 
                payload.getInt("statusCode"),
                payload.get("content")
            )
        );
    }
}

