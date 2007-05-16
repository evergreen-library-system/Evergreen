package org.opensrf.test;
import org.opensrf.*;
import org.opensrf.util.*;
import java.util.List;
import java.util.ArrayList;

public class TestCache {
    public static void main(String args[]) throws Exception {

        /**
         * args is a list of string like so:  server:port server2:port server3:port ...
         */

        Cache.initCache(args);
        Cache cache = new Cache();

        cache.set("key1", "HI, MA!");
        cache.set("key2", "HI, MA! 2");
        cache.set("key3", "HI, MA! 3");

        System.out.println("got key1 = " + (String) cache.get("key1"));
        System.out.println("got key2 = " + (String) cache.get("key2"));
        System.out.println("got key3 = " + (String) cache.get("key3"));
    }
}


