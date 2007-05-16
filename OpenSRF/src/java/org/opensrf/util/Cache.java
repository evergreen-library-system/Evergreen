package org.opensrf.util;
import com.danga.MemCached.*;
import java.util.List;

/**
 * Memcache client
 */
public class Cache extends MemCachedClient {

    public Cache() {
        super();
        setCompressThreshold(4096); /* ?? */
    }

    /**
     * Initializes the cache client
     * @param serverList Array of server:port strings specifying the
     * set of memcache servers this client will talk to
     */
    public static void initCache(String[] serverList) {
        SockIOPool pool = SockIOPool.getInstance();
        pool.setServers(serverList);
        pool.initialize();      
        com.danga.MemCached.Logger logger = 
            com.danga.MemCached.Logger.getLogger(MemCachedClient.class.getName());
        logger.setLevel(logger.LEVEL_ERROR);
    }

    /**
     * Initializes the cache client
     * @param serverList List of server:port strings specifying the
     * set of memcache servers this client will talk to
     */
    public static void initCache(List<String> serverList) {
        initCache(serverList.toArray(new String[]{}));
    }
}

