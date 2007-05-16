package org.opensrf.test;
import org.opensrf.*;
import org.opensrf.util.*;

public class TestConfig {
    public static void main(String args[]) throws Exception {
        Config config = new Config("");
        config.parse(args[0]);
        Config.setConfig(config);
        System.out.println(config);
        System.out.println("");

        for(int i = 1; i < args.length; i++) 
            System.out.println("Found config value: " + args[i] + ": " + Config.global().get(args[i]));
    }
}
