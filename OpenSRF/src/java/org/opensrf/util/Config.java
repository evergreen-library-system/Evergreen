package org.opensrf.util;

import org.json.*;
import java.util.Map;
import java.util.List;


/**
 * Config reader and accesor module.  This module reads an XML config file,
 * then loads the file into an internal config, whose values may be accessed
 * by xpath-style lookup paths.
 */
public class Config {

    /** The globl config instance */
    private static Config config;
    /** The object form of the parsed config */
    private Map configObject;
    private String context;

    public Config(String context) {
        this.context = context;
    }

    /**
     * Sets the global config object.
     * @param c The config object to use.
     */
    public static void setConfig(Config c) {
        config = c;
    }

    /**
     * Parses an XML config file.
     * @param filename The path to the file to parse.
     */
    public void parse(String filename) throws Exception {
        String xml = Utils.fileToString(filename);
        JSONObject jobj = XML.toJSONObject(xml);
        configObject = (Map) new JSONReader(jobj.toString()).readObject();
    }

    /**
     * Returns the configuration value found at the requested path.
     * @see org.opensrf.util.Utils.findPath for path description.
     * @param path The search path
     * @return The config value, or null if no value exists at the given path.  
     * @throws ConfigException thrown if nothing is found at the path
     */
    public static String getString(String path) throws ConfigException {
        try {
            return (String) get(path);
        } catch(Exception e) {
            throw new 
                ConfigException("No config string found at " + path);
        }
    }

    public static int getInt(String path) throws ConfigException {
        return Integer.parseInt(getString(path));
    }

    /**
     * Returns the configuration object found at the requested path.
     * @see org.opensrf.util.Utils.findPath for path description.
     * @param path The search path
     * @return The config value
     * @throws ConfigException thrown if nothing is found at the path
     */
    public static Object get(String path) throws ConfigException {
        try {
            Object obj = Utils.findPath(config.configObject, config.context + path);
            if(obj == null)
                throw new ConfigException("");
            return obj;
        } catch(Exception e) {
            e.printStackTrace();
            throw new ConfigException("No config object found at " + path);
        }
    }

    public static Object getFirst(String path) throws ConfigException {
        Object obj = get(path); 
        if(obj instanceof List) 
            return ((List) obj).get(0);
        return obj;
    }


    /**
     * Returns the config as a JSON string
     */
    public String toString() {
        return new JSONWriter(configObject).write();
    }
}

