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
        if(args.length < 3) {
            out.println( "usage: org.opensrf.test.TestClient "+
                "<osrfConfigFile> <service> <method> [<JSONparam1>, <JSONparam2>]");
            return;
        }

        Sys.bootstrapClient(args[0], "/config/opensrf");
        String service = args[1];
        String method = args[2];

        /** build the client session and send the request */
        ClientSession session = new ClientSession(service);
        List<Object> params = new ArrayList<Object>();
        JSONReader reader;

        for(int i = 3; i < args.length; i++) /* add the params */
            params.add(new JSONReader(args[i]).read());


        Result result;

        long start = new Date().getTime();
        Request request = session.request(method, params);

        while( (result = request.recv(60000)) != null ) { 
            /** loop over the results and print the JSON version of the content */

            if(result.getStatusCode() != 200) { /* make sure the request succeeded */
                out.println("status = " + result.getStatus());
                out.println("status code = " + result.getStatusCode());
                continue;
            }

            out.println("result JSON: " + new JSONWriter(result.getContent()).write());
        }
        out.println("Request round trip took: " + (new Date().getTime() - start) + " ms.");
    }
}



