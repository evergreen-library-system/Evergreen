package org.opensrf.net.xmpp;

import javax.xml.stream.*;
import javax.xml.stream.events.* ;
import javax.xml.namespace.QName;
import java.util.Queue;
import java.io.InputStream;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.Date;


/**
 * Slim XMPP Stream reader.  This reader only understands enough XMPP
 * to handle logins and recv messages.  It's implemented as a StAX parser.
 * @author Bill Erickson, Georgia Public Library Systems
 */
public class XMPPReader implements Runnable {

    /** Queue of received messages. */
    private Queue<XMPPMessage> msgQueue;
    /** Incoming XMPP XML stream */
    private InputStream inStream;
    /** Current message body */
    private StringBuffer msgBody;
    /** Current message thread */
    private StringBuffer msgThread;
    /** Current message status */
    private StringBuffer msgStatus;
    /** Current message error type */
    private StringBuffer msgErrType;
    /** Current message sender */
    private String msgFrom;
    /** Current message recipient */
    private String msgTo;
    /** Current message error code */
    private int msgErrCode;

    /** Where this reader currently is in the document */
    private XMLState xmlState;

    /** The current connect state to the XMPP server */
    private XMPPStreamState streamState;


    /** Used to represent out connection state to the XMPP server */
    public static enum XMPPStreamState {
        DISCONNECTED,   /* not connected to the server */
        CONNECT_SENT,   /* we've sent the initial connect message */
        CONNECT_RECV,   /* we've received a response to our connect message */
        AUTH_SENT,      /* we've sent an authentication request */
        CONNECTED       /* authentication is complete */
    };


    /** Used to represents where we are in the XML document stream. */
    public static enum XMLState {
        IN_NOTHING,
        IN_BODY,
        IN_THREAD,
        IN_STATUS
    };


    /**
     * Creates a new reader. Initializes the message queue.
     * Sets the stream state to disconnected, and the xml
     * state to in_nothing.
     * @param inStream the inbound XML stream
     */
    public XMPPReader(InputStream inStream) {
        msgQueue = new ConcurrentLinkedQueue<XMPPMessage>();
        this.inStream = inStream;
        resetBuffers();
        xmlState = XMLState.IN_NOTHING;
        streamState = XMPPStreamState.DISCONNECTED;
    }

    /**
     * Change the connect state and notify that a core 
     * event has occurred.
     */
    protected void setXMPPStreamState(XMPPStreamState state) {
        streamState = state;
        notifyCoreEvent();
    }

    /**
     * @return The current stream state of the reader 
     */
    public XMPPStreamState getXMPPStreamState() {
        return streamState;
    }


    /**
     * @return The next message in the queue, or null
     */
    public XMPPMessage popMessageQueue() {
        return (XMPPMessage) msgQueue.poll();
    }


    /**
     * Initializes the message buffers 
     */
    private void resetBuffers() {
        msgBody = new StringBuffer();
        msgThread = new StringBuffer();
        msgStatus = new StringBuffer(); 
        msgErrType = new StringBuffer();
        msgFrom = "";
        msgTo = "";
    }


    /**
     * Notifies the waiting thread that a core event has occurred.
     * Each reader should have exactly one dependent session thread. 
     */
    private synchronized void notifyCoreEvent() {
        notify();
    }


    /**
     * Waits up to timeout milliseconds for a core event to occur. 
     * Also, having a message already waiting in the queue 
     * constitutes a core event.
     * @param timeout The number of milliseconds to wait.  If 
     * timeout is negative, waits potentially forever.
     * @return The number of milliseconds in wait
     */
    public synchronized long waitCoreEvent(long timeout) {

        if(msgQueue.peek() != null || timeout == 0) return 0;

        long start = new Date().getTime();
        try{
            if(timeout < 0) wait();
            else wait(timeout);
        } catch(InterruptedException ie) {}

        return new Date().getTime() - start;
    }



    /** Kickoff the thread */
    public void run() {
        read();
    }


    /**
     * Parses XML data from the provided XMPP stream.
     */
    public void read() {

        try {

            XMLInputFactory factory = XMLInputFactory.newInstance();

            /** disable as many unused features as possible to speed up the parsing */
            factory.setProperty(XMLInputFactory.IS_REPLACING_ENTITY_REFERENCES, Boolean.FALSE);
            factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, Boolean.FALSE);
            factory.setProperty(XMLInputFactory.IS_NAMESPACE_AWARE, Boolean.FALSE);
            factory.setProperty(XMLInputFactory.IS_COALESCING, Boolean.FALSE);
            factory.setProperty(XMLInputFactory.SUPPORT_DTD, Boolean.FALSE);

            /** create the stream reader */
            XMLStreamReader reader = factory.createXMLStreamReader(inStream);
            int eventType;

            while(reader.hasNext()) {
                /** cycle through the XML events */

                eventType = reader.next();

                switch(eventType) {

                    case XMLEvent.START_ELEMENT:
                        handleStartElement(reader);
                        break;

                    case XMLEvent.CHARACTERS:
                        switch(xmlState) {
                            case IN_BODY:
                                msgBody.append(reader.getText());
                                break;
                            case IN_THREAD:
                                msgThread.append(reader.getText());
                                break;
                            case IN_STATUS:
                                msgStatus.append(reader.getText());
                                break;
                        }
                        break;

                    case XMLEvent.END_ELEMENT: 
                        xmlState = XMLState.IN_NOTHING;
                        if("message".equals(reader.getName().toString())) {

                           /** build a message and add it to the message queue */
                           XMPPMessage msg = new XMPPMessage();
                           msg.setFrom(msgFrom);
                           msg.setTo(msgTo);
                           msg.setBody(msgBody.toString());
                           msg.setThread(msgThread.toString());

                           msgQueue.offer(msg);
                           resetBuffers(); 
                           notifyCoreEvent();
                        }
                        break;
                }
            }

        } catch(javax.xml.stream.XMLStreamException se) {
            /* XXX log an error */
            xmlState = XMLState.IN_NOTHING;
            streamState = XMPPStreamState.DISCONNECTED;
            notifyCoreEvent();
        }
    }


    /**
     * Handles the start_element event.
     */
    private void handleStartElement(XMLStreamReader reader) {

        String name = reader.getName().toString();

        if("message".equals(name)) {
            xmlState = XMLState.IN_BODY;

            /** add a special case for the opensrf "router_from" attribute */
            String rf = reader.getAttributeValue(null, "router_from");
            if( rf != null )
                msgFrom = rf;
            else
                msgFrom = reader.getAttributeValue(null, "from");
            msgTo = reader.getAttributeValue(null, "to");
            return;
        }

        if("body".equals(name)) {
            xmlState = XMLState.IN_BODY;
            return;
        }

        if("thread".equals(name)) {
            xmlState = XMLState.IN_THREAD;
            return;
        }

        if("stream:stream".equals(name)) {
            setXMPPStreamState(XMPPStreamState.CONNECT_RECV);
            return;
        }

        if("iq".equals(name)) {
            if("result".equals(reader.getAttributeValue(null, "type")))
                setXMPPStreamState(XMPPStreamState.CONNECTED);
            return;
        }

        if("status".equals(name)) {
            xmlState = XMLState.IN_STATUS;
            return;
        }

        if("stream:error".equals(name)) {
            setXMPPStreamState(XMPPStreamState.DISCONNECTED);
            return;
        }

        if("error".equals(name)) {
            msgErrType.append(reader.getAttributeValue(null, "type"));
            msgErrCode = Integer.parseInt(reader.getAttributeValue(null, "code"));
            setXMPPStreamState(XMPPStreamState.DISCONNECTED);
            return;
        }
    }
}




