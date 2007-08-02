package org.open_ils.idl;

public class IDLException extends Exception {
    public IDLException(String info) {
        super(info);
    }
    public IDLException(String info, Throwable cause) {
        super(info, cause);
    }
}
