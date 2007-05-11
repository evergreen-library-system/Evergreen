package org.opensrf.net.xmpp;

import java.io.*;

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
}


