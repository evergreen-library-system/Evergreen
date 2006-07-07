// so we can tell if it's a book or other type
load_lib('fmall.js');
load_lib('fmgen.js');
load_lib('record_type.js');

var marcdoc = new XML(environment.marc);
var marc_ns = new Namespace('http://www.loc.gov/MARC21/slim');

default xml namespace = marc_ns;

environment.result = new mrd();

environment.result.item_type( extractFixedField( marcdoc, 'Type' ) );
environment.result.item_form( extractFixedField( marcdoc, 'Form' ) );
environment.result.bib_level( extractFixedField( marcdoc, 'BLvl' ) );
environment.result.control_type( extractFixedField( marcdoc, 'Ctrl' ) );
environment.result.enc_level( extractFixedField( marcdoc, 'ELvl' ) );
environment.result.audience( extractFixedField( marcdoc, 'Audn' ) );
environment.result.lit_form( extractFixedField( marcdoc, 'LitF' ) );
environment.result.type_mat( extractFixedField( marcdoc, 'TMat' ) );
environment.result.cat_form( extractFixedField( marcdoc, 'Desc' ) );
environment.result.pub_status( extractFixedField( marcdoc, 'DtSt' ) );
environment.result.item_lang( extractFixedField( marcdoc, 'Lang' ) );

