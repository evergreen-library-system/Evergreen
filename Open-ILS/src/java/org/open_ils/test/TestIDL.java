package org.open_ils.test;
import org.open_ils.idl.*;
import org.opensrf.*;
import org.opensrf.util.*;

public class TestIDL {
    public static void main(String args[]) throws Exception {
        String idlFile = args[0];
        IDLParser parser = new IDLParser(idlFile);
        parser.parse();
        //System.out.print(parser.toXML());

        OSRFObject bre = new OSRFObject("bre");
        bre.put("id", new Integer(1));
        bre.put("isnew", new Boolean(false));
        bre.put("isdeleted", new Boolean(true));
        System.out.println(bre);
        System.out.println(new JSONWriter(bre).write());
    }
}
