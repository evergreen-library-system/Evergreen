package org.opensrf.test;

import org.opensrf.net.xmpp.XMPPReader;
import org.opensrf.net.xmpp.XMPPMessage;
import org.opensrf.net.xmpp.XMPPSession;

public class TestXMPP {

    public static void main(String args[]) throws Exception {

        String host;
        int port;
        String username;
        String password;
        String resource;
        String recipient;

        try {
            host = args[0];
            port = Integer.parseInt(args[1]);
            username = args[2];
            password = args[3];
            resource = args[4];

        } catch(ArrayIndexOutOfBoundsException e) {
            System.err.println("usage: org.opensrf.test.TestXMPP <host> <port> <username> <password> <resource>");
            return;
        }

        XMPPSession session = new XMPPSession(host, port);
        session.connect(username, password, resource);

        XMPPMessage msg;

        if( args.length == 6 ) {
            /** they specified a recipient */
            recipient = args[5];
            msg = new XMPPMessage();
            msg.setTo(recipient);
            msg.setThread("test-thread");
            msg.setBody("Hello, from java-xmpp");
            System.out.println("Sending message to " + recipient);
            session.send(msg);
        }

        while(true) {
            System.out.println("waiting for message...");
            msg = session.recv(-1);
            System.out.println("got message: " + msg.toXML());
        }
    }
}





