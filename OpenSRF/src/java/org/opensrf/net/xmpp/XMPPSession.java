package org.opensrf.net.xmpp;

import java.io.*;
import java.net.Socket;


/**
 * Represents a single XMPP session.  Sessions are responsible for writing to
 * the stream and for managing a stream reader.
 */
public class XMPPSession {

    /** Initial jabber message */
    public static final String JABBER_CONNECT = 
        "<stream:stream to='%s' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>";

    /** Basic auth message */
    public static final String JABBER_BASIC_AUTH =  
        "<iq id='123' type='set'><query xmlns='jabber:iq:auth'>" +
        "<username>%s</username><password>%s</password><resource>%s</resource></query></iq>";

    /** jabber domain */
    private String host;
    /** jabber port */
    private int port;
    /** jabber username */
    private String username;
    /** jabber password */
    private String password;
    /** jabber resource */
    private String resource;

    /** XMPP stream reader */
    XMPPReader reader;
    /** Fprint-capable socket writer */
    PrintWriter writer;
    /** Raw socket output stream */
    OutputStream outStream;



    /**
     * Creates a new session.
     * @param host The jabber domain
     * @param port The jabber port
     */
    public XMPPSession( String host, int port ) {
        this.host = host;
        this.port = port;
    }


    /** true if this session is connected to the server */
    public boolean connected() {
        return (
            reader != null && 
            reader.getXMPPStreamState() == XMPPReader.XMPPStreamState.CONNECTED);
    }


    /**
     * Connects to the network.
     * @param username The jabber username
     * @param password The jabber password
     * @param resource The Jabber resource
     */
    public void connect(String username, String password, String resource) throws XMPPException {

        this.username = username;
        this.password = password;
        this.resource = resource;

        Socket socket;

        try { 
            /* open the socket and associated streams */
            socket = new Socket(host, port);

            /** the session maintains control over the output stream */
            outStream = socket.getOutputStream();
            writer = new PrintWriter(outStream, true);

            /** pass the input stream to the reader */
            reader = new XMPPReader(socket.getInputStream());

        } catch(IOException ioe) {
            throw new 
                XMPPException("unable to communicate with host " + host + " on port " + port);
        }

        /* build the reader thread */
        Thread thread = new Thread(reader);
        thread.setDaemon(true);
        thread.start();

        /* send the initial jabber message */
        sendConnect();
        reader.waitCoreEvent(10000);
        if( reader.getXMPPStreamState() != XMPPReader.XMPPStreamState.CONNECT_RECV ) 
            throw new XMPPException("unable to connect to jabber server");

        /* send the basic auth message */
        sendBasicAuth(); /* XXX add support for other auth mechanisms */
        reader.waitCoreEvent(10000);
        if(!connected())
            throw new XMPPException("Authentication failed");
    }

    /** Sends the initial jabber message */
    private void sendConnect() {
        writer.printf(JABBER_CONNECT, host);
        reader.setXMPPStreamState(XMPPReader.XMPPStreamState.CONNECT_SENT);
    }

    /** Send the basic auth message */
    private void sendBasicAuth() {
        writer.printf(JABBER_BASIC_AUTH, username, password, resource);
        reader.setXMPPStreamState(XMPPReader.XMPPStreamState.AUTH_SENT);
    }


    /**
     * Sends an XMPPMessage.
     * @param msg The message to send.
     */
    public void send(XMPPMessage msg) throws XMPPException {
        checkConnected();
        try {
            outStream.write(msg.toXML().getBytes()); 
        } catch (Exception e) {
            throw new XMPPException(e.toString());
        }
    }


    /**
     * @throws XMPPException if we are no longer connected.
     */
    private void checkConnected() throws XMPPException {
        if(!connected())
            throw new XMPPException("Disconnected stream");
    }


    /**
     * Receives messages from the network.  
     * @param timeout Maximum number of milliseconds to wait for a message to arrive.
     * If timeout is negative, this method will wait indefinitely.
     * If timeout is 0, this method will not block at all, but will return a 
     * message if there is already a message available.
     */
    public XMPPMessage recv(int timeout) throws XMPPException {

        XMPPMessage msg;

        if(timeout < 0) {

            while(true) { /* wait indefinitely for a message to arrive */
                reader.waitCoreEvent(timeout);
                msg = reader.popMessageQueue();
                if( msg != null ) return msg;
                checkConnected();
            }

        } else {

            while(timeout >= 0) { /* wait at most 'timeout' milleseconds for a message to arrive */
                timeout -= reader.waitCoreEvent(timeout);
                msg = reader.popMessageQueue();
                if( msg != null ) return msg;
                checkConnected();
            }
        }

        return null;
    }
}

