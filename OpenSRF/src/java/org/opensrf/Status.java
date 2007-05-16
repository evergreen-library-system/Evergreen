package org.opensrf;
import org.opensrf.util.*;

public class Status {

    public static final int CONTINUE            = 100;
    public static final int OK                  = 200;
    public static final int ACCEPTED            = 202;
    public static final int COMPLETE            = 205;
    public static final int REDIRECTED          = 307;
    public static final int EST                 = 400;
    public static final int STATUS_UNAUTHORIZED = 401;
    public static final int FORBIDDEN           = 403;
    public static final int NOTFOUND            = 404;
    public static final int NOTALLOWED          = 405;
    public static final int TIMEOUT             = 408;
    public static final int EXPFAILED           = 417;
    public static final int INTERNALSERVERERROR = 500;
    public static final int NOTIMPLEMENTED      = 501;
    public static final int VERSIONNOTSUPPORTED = 505;

    private OSRFRegistry registry = OSRFRegistry.registerObject(
        "osrfConnectStatus",
        OSRFRegistry.WireProtocol.HASH,
        new String[] {"status", "statusCode"});

    /** The name of the status */
    String status;
    /** The status code */
    int statusCode;

    public Status(String status, int statusCode) {
        this.status = status;
        this.statusCode = statusCode;
    }

    public int getStatusCode() {
        return statusCode;
    }
    public String getStatus() {
        return status;
    }

    /**
     * Implements the generic get() API required by OSRFSerializable
     */
    public Object get(String field) {
        if("status".equals(field))
            return getStatus();
        if("statusCode".equals(field))
            return new Integer(getStatusCode());
        return null;
    }

    /**
     * @return The osrfMessage registry.
     */
    public OSRFRegistry getRegistry() {
        return registry;
    }
}


