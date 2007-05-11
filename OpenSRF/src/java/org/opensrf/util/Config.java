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
    /** 
     * The log parsing context.  This is used as a prefix to the
     * config item search path.  This allows config XML chunks to 
     * be inserted into arbitrary XML files.
     */
    private String context;

    /**
     * @param context The config context
     */
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

    /**
     * Gets the int value at the given path
     * @param path The search path
     */
    public static int getInt(String path) throws ConfigException {
        try {
            return Integer.parseInt(getString(path));
        } catch(Exception e) {
            throw new
                ConfigException("No config int found at " + path);
        }
    }

    /**
     * Returns the configuration object found at the requested path.
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

    /**
     * Returns the first item in the list found at the given path.  If
     * no list is found, ConfigException is thrown.
     * @param path The search path
     */
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

