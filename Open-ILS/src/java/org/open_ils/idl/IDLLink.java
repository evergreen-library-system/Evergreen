package org.open_ils.idl;


public class IDLLink {

   /**The field on the IDLObject this link extends from */
   private String field;
   private String reltype;
   private String key;
   private String map;
   /**The IDL class linked to */
   private String IDLClass;


   public void setField(String field) {
      this.field = field;
   }
   public void setReltype(String reltype) {
      this.reltype = reltype;
   }
   public void setKey(String key) {
      this.key = key;
   }
   public void setMap(String map) {
      this.map = map;
   }
   public void setIDLClass(String IDLClass) {
      this.IDLClass = IDLClass;
   }
   public String getField() {
      return this.field;
   }
   public String getReltype() {
      return this.reltype;
   }
   public String getKey() {
      return this.key;
   }
   public String getMap() {
      return this.map;
   }
   public String getIDLClass() {
      return this.IDLClass;
   }
}

