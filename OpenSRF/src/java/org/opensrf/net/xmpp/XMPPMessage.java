package org.opensrf.net.xmpp;

import java.io.*;


/*
 * uncomment to use the DOM serialization code...
 
import org.w3c.dom.*;
import org.apache.xerces.dom.DocumentImpl;
import org.apache.xerces.dom.DOMImplementationImpl;
import org.apache.xml.serialize.OutputFormat;
import org.apache.xml.serialize.Serializer;
import org.apache.xml.serialize.SerializerFactory;
import org.apache.xml.serialize.XMLSerializer;
*/


/**
 * Models a single XMPP message.
 */
public class XMPPMessage {

    /** Message body */
    private String body;
    /** Message recipient */
    private String to;
    /** Message sender */
    private String from;
    /** Message thread */
    private String thread;
    /** Message xid */
    private String xid;

    public XMPPMessage() {
    }

    public String getBody() {
        return body;
    }
    public String getTo() { 
        return to; 
    }
    public String getFrom() { 
        return from;
    }
    public String getThread() { 
        return thread; 
    }
    public String getXid() {
        return xid;
    }
    public void setBody(String body) {
        this.body = body;
    }
    public void setTo(String to) { 
        this.to = to; 
    }
    public void setFrom(String from) { 
        this.from = from; 
    }
    public void setThread(String thread) { 
        this.thread = thread; 
    }
    public void setXid(String xid) {
        this.xid = xid; 
    }


    /**
     * Generates the XML representation of this message.
     */
    public String toXML() {
        StringBuffer sb = new StringBuffer("<message to='");
        escapeXML(to, sb);
        sb.append("' osrf_xid='");
        escapeXML(xid, sb);
        sb.append("'><thread>");
        escapeXML(thread, sb);
        sb.append("</thread><body>");
        escapeXML(body, sb);
        sb.append("</body></message>");
        return sb.toString();
    }


    /**
     * Escapes non-valid XML characters.
     * @param s The string to escape.
     * @param sb The StringBuffer to append new data to.
     */
    private void escapeXML(String s, StringBuffer sb) {
        if( s == null ) return;
        char c;
        int l = s.length();
        for( int i = 0; i < l; i++ ) {
            c = s.charAt(i);
            switch(c) {
                case '<': 
                    sb.append("&lt;");
                    break;
                case '>': 
                    sb.append("&gt;");
                    break;
                case '&': 
                    sb.append("&amp;");
                    break;
                default:
                    sb.append(c);
            }
        }
    }



    /**
     * This is a DOM implementataion of message serialization. 
     * I'm inclined to think the stringbuffer version is faster, but 
     * I have no proof.
     */
    /*
    public String __toXML() {

        Document doc = new DocumentImpl();
        Element message = doc.createElement("message");
        Element body = doc.createElement("body");
        Element thread = doc.createElement("thread");

        doc.appendChild(message);
        message.setAttribute("to", getTo());
        message.setAttribute("from", getFrom());
        message.appendChild(body);
        message.appendChild(thread);

        body.appendChild(doc.createTextNode(getBody()));
        thread.appendChild(doc.createTextNode(getThread()));

        XMLSerializer serializer = new XMLSerializer();
        StringWriter strWriter = new StringWriter();
        OutputFormat outFormat = new OutputFormat();

        outFormat.setEncoding("UTF-8");
        outFormat.setVersion("1.0");
        outFormat.setIndenting(false);
        outFormat.setOmitXMLDeclaration(true);

        serializer.setOutputCharStream(strWriter);
        serializer.setOutputFormat(outFormat);

        try {
            serializer.serialize(doc);
        } catch(IOException ioe) {
        }
        return strWriter.toString();
    }
    */
}


