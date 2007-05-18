package org.opensrf.test;
import org.opensrf.*;
import org.opensrf.util.*;
import java.util.Date;
import java.util.List;
import java.util.ArrayList;
import java.io.PrintStream;


public class MathBench {

    public static void main(String args[]) throws Exception {

        PrintStream out = System.out;

        if(args.length < 2) {
            out.println("usage: java org.opensrf.test.MathBench <osrfConfig> <numIterations>");
            return;
        }

        /** connect to the opensrf network */
        Sys.bootstrapClient(args[0], "/config/opensrf");

        /** how many iterations */
        int count = Integer.parseInt(args[1]);

        /** create the client session */
        ClientSession session = new ClientSession("opensrf.math");

        /** params are 1,2 */
        List<Object> params = new ArrayList<Object>();
        params.add(new Integer(1));
        params.add(new Integer(2));

        Request request;
        Result result;
        long start;
        double total = 0;

        for(int i = 0; i < count; i++) {

            start = new Date().getTime();

            /** create (and send) the request */
            request = session.request("add", params);

            /** wait up to 3 seconds for a response */
            result = request.recv(3000);

            /** collect the round-trip time */
            total += new Date().getTime() - start;

            if(result.getStatusCode() == Status.OK) {
                out.print("+");
            } else {
                out.println("\nrequest failed");
                out.println("status = " + result.getStatus());
                out.println("status code = " + result.getStatusCode());
            }

            /** remove this request from the session's request set */
            request.cleanup();

            if((i+1) % 100 == 0) /** print 100 responses per line */
                out.println(" [" + (i+1) + "]");
        }

        out.println("\nAverage request time is " + (total/count) + " ms");
        
        /** remove this session from the global session cache */
        session.cleanup();

        /** disconnect from the opensrf network */
        Sys.shutdown();
    }
}



