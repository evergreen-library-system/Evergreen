package org.opensrf.util;

import java.io.*;
import java.util.*;

/**
 * Collection of general, static utility methods
 */
public class Utils {

    /**
     * Returns the string representation of a given file.
     * @param filename The file to turn into a string
     */
    public static String fileToString(String filename) 
            throws FileNotFoundException, IOException {

        StringBuffer sb = new StringBuffer();
        BufferedReader in = new BufferedReader(new FileReader(filename));
        String str;
        while ((str = in.readLine()) != null) 
            sb.append(str);
        in.close();
        return sb.toString();
    }


    /**
     * @see escape(String, StringBuffer)
     */
    public static String escape(String string) {
        StringBuffer sb = new StringBuffer();
        escape(string, sb);
        return sb.toString();
    }

    /**
     * Escapes a string.  Turns bare newlines into \n, etc.
     * Escapes \n, \r, \t, ", \f
     * Encodes non-ascii characters as UTF-8: \u0000
     * @param string The string to escape
     * @param sb The string buffer to write the escaped string into
     */
    public static void escape(String string, StringBuffer sb) {
        int len = string.length();
        String utf;
        char c;
        for( int i = 0; i < len; i++ ) {
            c = string.charAt(i);
            switch (c) {
                case '\\':
                    sb.append("\\\\");
                    break;
                case '"':
                    sb.append("\\\"");
                    break;
                case '\b':
                    sb.append("\\b");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                default:
                    if (c < 32 || c > 126 ) { 
                        /* escape all non-ascii or control characters as UTF-8 */
                        utf = "000" + Integer.toHexString(c);
                        sb.append("\\u" + utf.substring(utf.length() - 4));
                    } else {
                        sb.append(c);
                    }
            }
        }
    }
}



