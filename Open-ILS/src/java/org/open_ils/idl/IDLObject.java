package org.open_ils.idl;
import java.util.HashMap;
import java.util.Iterator;


public class IDLObject {

    private String IDLClass;
    private String fieldMapper;
    private String controller;
    private String rptLabel;
    private HashMap<String, IDLField> fields;
    private HashMap<String, IDLLink> links;
    
    /** true if this is a virtual object (does not live in the database) */
    private boolean isVirtual;
    
    public IDLObject() {
       fields = new HashMap<String, IDLField>();
       links = new HashMap<String, IDLLink>();
    }
    
    public String getIDLClass() {
       return IDLClass;
    }
    
    public void addLink(IDLLink link) {
       links.put(link.getField(), link);
    }
    
    public void addField(IDLField field) {
       fields.put(field.getName(), field);
    }
    
    public IDLField getField(String name) {
        return (IDLField) fields.get(name);
    }

    public HashMap getFields() {
        return fields;
    }


    /**
     * Returns the link object found at the given field on 
     * this IDLObject.
     */
    public IDLLink getLink(String fieldName) {
        return (IDLLink) links.get(fieldName);
    }
    
    public String getFieldMapper() {
       return fieldMapper;
    }
    
    public String getController() {
       return controller;
    }
    
    public String getRptLabel() {
       return rptLabel;
    }
    public boolean isVirtual() {
       return isVirtual;
    }
    
    public void setIDLClass(String IDLClass) {
       this.IDLClass = IDLClass;
    }
    
    public void setFieldMapper(String fm) {
       this.fieldMapper = fm;
    }
    public void setController(String controller) {
       this.controller = controller;
    }
    public void setRptLabel(String label) {
       this.rptLabel = label;
    }
    public void setIsVirtual(boolean isVirtual) {
       this.isVirtual = isVirtual;
    }


    public void toXML(StringBuffer sb) {

        sb.append("\t\t<fields>");
        Iterator itr = fields.keySet().iterator();        
        IDLField field;
        while(itr.hasNext()) {
            field = fields.get((String) itr.next()); 
            field.toXML(sb);
        }
        sb.append("\t\t</fields>");
    }
}
