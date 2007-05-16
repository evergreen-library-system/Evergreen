package org.opensrf.test;
import org.opensrf.*;
import org.opensrf.util.*;
import java.util.Map;
import java.util.Date;
import java.util.List;
import java.util.ArrayList;
import java.io.PrintStream;


public class TestClient {
    public static void main(String args[]) throws Exception {
        
        PrintStream out = System.out;
        String service;
        String method;

        try {
            Sys.bootstrapClient(args[0], "/config/opensrf");
            service = args[1];
            method = args[2];
        } catch(ArrayIndexOutOfBoundsException e) {
            out.println( "usage: org.opensrf.test.TestClient "+
                "<osrfConfigFile> <service> <method> [<JSONparam1>, <JSONparam2>]");
            return;
        }

        /** build the client session and send the request */
        ClientSession session = new ClientSession(service);
        List<Object> params = new ArrayList<Object>();
        JSONReader reader;

        for(int i = 3; i < args.length; i++) /* add the params */
            params.add(new JSONReader(args[i]).read());

        Request request = session.request(method, params);

        Result result;
        long start = new Date().getTime();
        while( (result = request.recv(60000)) != null ) {
            out.println("status = " + result.getStatus());
            out.println("status code = " + result.getStatusCode());
            out.println("result JSON: " + new JSONWriter(result.getContent()).write());
        }
        out.println("Request took: " + (new Date().getTime() - start));
    }
}



