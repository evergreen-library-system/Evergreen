package org.open_ils.idl;

public class IDLField {

    /** Field name */
    private String name;

    /** Where this field resides in the array when serilized */
    private int arrayPos;

    /** True if this field does not belong in the database */
    private boolean isVirtual;

    public void setName(String name) {
      this.name = name;
    }
    public void setArrayPos(int arrayPos) {
      this.arrayPos = arrayPos;
    }
    public void setIsVirtual(boolean isVirtual) {
      this.isVirtual = isVirtual;
    }
    public String getName() {
      return this.name;
    }
    public int getArrayPos() {
      return this.arrayPos;
    }
    public boolean getIsVirtual() {
      return this.isVirtual;
    }

    public void toXML(StringBuffer sb) {
        sb.append("\t\t\t<field name='");
        sb.append(name);
        sb.append("' ");
        sb.append(IDLParser.OILS_NS_OBJ_PREFIX);
        sb.append(":array_position='");
        sb.append(arrayPos);
        sb.append("' ");
        sb.append(IDLParser.OILS_NS_PERSIST_PREFIX);
        sb.append(":virtual='");
        sb.append(isVirtual);
        sb.append("'/>\n");
    }
}
