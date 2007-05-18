package org.open_ils.test;
import org.open_ils.idl.*;

public class TestIDL {
    public static void main(String args[]) throws Exception {
        String idlFile = args[0];
        IDLParser parser = new IDLParser(idlFile);
        parser.parse();
        System.out.print(parser.toXML());
    }
}
