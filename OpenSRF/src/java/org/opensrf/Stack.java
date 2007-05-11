package org.opensrf;
import org.opensrf.net.xmpp.XMPPMessage;
import org.opensrf.util.*;
import java.util.Date;
import java.util.List;
import java.util.Iterator;


public class Stack {

    public static void processXMPPMessage(XMPPMessage msg) {

        if(msg == null) return;

        Session ses = Session.findCachedSession(msg.getThread());

        if(ses == null) {
            /** inbound client request, create a new server session */
            return;
        }

        /** parse the JSON message body, which should result in a list of OpenSRF messages */
        List msgList; 

        try {
            msgList = new JSONReader(msg.getBody()).readArray();
        } catch(JSONException e) {
            /** XXX LOG error */
            e.printStackTrace();
            return;
        }

        Iterator itr = msgList.iterator();

        OSRFObject obj = null;
        long start = new Date().getTime();

        while(itr.hasNext()) {

            /** Construct a Message object from the generic OSRFObject returned from parsing */
            obj = (OSRFObject) itr.next();

            processOSRFMessage(
                ses, 
                new Message(
                    obj.getInt("threadTrace"),
                    obj.getString("type"),
                    obj.get("payload")
                )
            );
        }

        /** LOG the duration */
    }

    public static void processOSRFMessage(Session ses, Message msg) {
        if( ses instanceof ClientSession ) 
            processResponse((ClientSession) ses, msg);
        else
            processRequest((ServerSession) ses, msg);
    }

    public static void processResponse(ClientSession session, Message msg) {
        if(msg.RESULT.equals(msg.getType())) {
            session.pushResponse(msg);
            return;
        }
    }

    public static void processRequest(ServerSession session, Message msg) {
    }
}
