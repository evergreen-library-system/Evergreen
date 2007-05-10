package org.opensrf;
import java.util.Date;
import java.util.List;
import java.util.ArrayList;
import java.util.Random;

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
     * @param service The remove service to communicate with
     */
    public ClientSession(String service) throws ConfigException {
        this.service = service;
        domain = (String) Config.getFirst("/domain/domains");
        router = (String) Config.getString("/router_name");
        setRemoteNode(router + "@" + domain + "/" + service);
        origRemoteNode = getRemoteNode();
        requests = new ArrayList<Request>();
        nextId = 0;
        long time = new Date().getTime();
        Random rand = new Random(time);
        thread = rand.nextInt()+""+rand.nextInt()+""+time;
        cacheSession();
    }
}

