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

        Sys.bootstrapClient(args[0], "/config/opensrf");
        int count = Integer.parseInt(args[1]);

        ClientSession session = new ClientSession("opensrf.math");
        List<Object> params = new ArrayList<Object>();
        params.add(new Integer(1));
        params.add(new Integer(2));

        Request request;
        Result result;
        long start;
        double total = 0;

        for(int i = 0; i < count; i++) {

            start = new Date().getTime();
            request = session.request("add", params);
            result = request.recv(5000);
            total += new Date().getTime() - start;

            if(result.getStatusCode() == Status.OK) {
                out.print("+");
            } else {
                out.println("\nrequest failed");
                out.println("status = " + result.getStatus());
                out.println("status code = " + result.getStatusCode());
            }

            request.cleanup();

            if((i+1) % 100 == 0) /* print 100 per line */
                out.println("");
        }

        out.println("\nAverage request time is " + (total/count) + " ms");
        Sys.shutdown();
    }
}



