'use strict';

describe('egVolCopyTest', function(){
  beforeEach(module('egVolCopy'));

  /** itemSvc tests **/
  describe('itemSvcTests', function() {

    it('itemSvc should start with empty lists', inject(function(itemSvc) {
        expect(itemSvc.copies.length).toEqual(0);
    }));

    it('itemSvc.convert_xul_templates converts copy templates as expected', inject(function(itemSvc) {
        var xul = JSON.parse('{"Easy Reader 1":{"Circulation Library":{"field":"circ_lib","type":"attribute","value":"4"},"Status":{"field":"status","type":"attribute","value":"0"},"Location/Collection":{"field":"location","value":"103","type":"attribute"},"Deposit?":{"field":"deposit","value":"f","type":"attribute"},"Copy Number":{"field":"copy_number","value":"1","type":"attribute"},"Price":{"type":"attribute","value":"25.55","field":"price"},"Loan Duration":{"value":"2","type":"attribute","field":"loan_duration"},"Circulate?":{"field":"circulate","type":"attribute","value":"t"},"Holdable?":{"field":"holdable","type":"attribute","value":"t"},"Circulation Modifier":{"field":"circ_modifier","value":"<HACK:KLUDGE:NULL>","type":"attribute"},"Floating?":{"field":"floating","value":"<HACK:KLUDGE:NULL>","type":"attribute"},"Owning Lib : Call Number":{"value":"4","type":"owning_lib","field":null},"Reference?":{"field":"ref","type":"attribute","value":"f"},"Quality":{"type":"attribute","value":"t","field":"mint_condition"},"Acquisition Cost":{"field":"cost","type":"attribute","value":"25.55"},"OPAC Visible?":{"type":"attribute","value":"t","field":"opac_visible"},"Deposit Amount":{"field":"deposit_amount","type":"attribute","value":"1.25"},"Fine Level":{"field":"fine_level","type":"attribute","value":"2"},"Circulate as Type":{"field":"circ_as_type","type":"attribute","value":"a"},"Age-based Hold Protection":{"value":"<HACK:KLUDGE:NULL>","type":"attribute","field":"age_protect"}},"Reference (unified)":{"volume_copy_creator.batch_class_menulist":{"field":"batch_class_menulist","type":"volume_copy_creator","value":"2"},"volume_copy_creator.batch_suffix_menulist":{"value":"1","type":"volume_copy_creator","field":"batch_suffix_menulist"},"volume_copy_creator.batch_prefix_menulist":{"type":"volume_copy_creator","value":"1","field":"batch_prefix_menulist"},"Location/Collection":{"field":"location","value":"102","type":"attribute"}}}');
        var webstaff = JSON.parse('{"Reference (unified)":{"callnumber":{"classification":2,"prefix":1,"suffix":1},"location":102},"Easy Reader 1":{"location":103,"circ_as_type":"a","status":0,"copy_number":1,"circ_lib":4,"ref":"f","circulate":"t","mint_condition":"t","cost":25.55,"deposit_amount":1.25,"deposit":"f","price":25.55,"opac_visible":"t","fine_level":2,"loan_duration":2,"holdable":"t"}}');
        expect(itemSvc.convert_xul_templates(xul)).toEqual(webstaff);
    }));

  });

});
