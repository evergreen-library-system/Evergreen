from django.db import models
from django.db.models import signals
from django.dispatch import dispatcher
import datetime
from gettext import gettext as _

INTERVAL_HELP_TEXT = _('examples: "1 hour", "14 days", "3 months", "DD:HH:MM:SS.ms"')
CHAR_MAXLEN=200 # just provide a sane default


""" --------------------------------------------------------------
    Permission tables
    -------------------------------------------------------------- """


class PermList(models.Model):
    code = models.CharField(maxlength=100)
    description = models.TextField(blank=True)
    class Admin:
        list_display = ('code','description')
        search_fields = ['code']
    class Meta:
        db_table = 'perm_list'
        ordering = ['code']
        verbose_name = _('Permission')
    def __str__(self):
        return self.code

class GrpPermMap(models.Model):
    grp_id = models.ForeignKey('GrpTree', db_column='grp')
    perm_id = models.ForeignKey(PermList, db_column='perm')
    depth_id = models.ForeignKey('OrgUnitType', to_field='depth', db_column='depth')
    grantable = models.BooleanField()
    class Admin:
        list_filter = ['grp_id']
        list_display = ('perm_id', 'grp_id', 'depth_id')
    class Meta:
        db_table = 'grp_perm_map'
        ordering = ['perm_id', 'grp_id']
        verbose_name = _('Permission Setting')
    def __str__(self):
        return str(self.grp_id)+' -> '+str(self.perm_id)

class GrpTree(models.Model):
    name = models.CharField(maxlength=100)
    parent_id = models.ForeignKey('self', null=True, related_name='children', db_column='parent')
    description = models.CharField(blank=True, maxlength=CHAR_MAXLEN)
    perm_interval = models.CharField(blank=True, maxlength=100, help_text=INTERVAL_HELP_TEXT)
    application_perm = models.CharField(blank=True, maxlength=100)
    usergroup = models.BooleanField()
    class Admin:
        list_display = ('name', 'description')
        list_filter = ['parent_id']
        search_fields = ['name', 'description']
    class Meta:
        db_table = 'grp_tree'
        ordering = ['name']
        verbose_name = _('User Group')
    def __str__(self):
        return self.name





""" There's no way to do user-based mangling given the size of the data without custom handling.
      When you try to create a new permission map, it tries to load all users into a dropdown selector :(

class User(models.Model):
   card_id = models.ForeignKey('Card', db_column='card')
   profile_id = models.ForeignKey(GrpTree, db_column='profile')
   usrname = models.CharField(blank=False, null=False, maxlength=CHAR_MAXLEN)
   def __str__(self):
      return "%s (%s)" % ( str(self.card_id), str(self.usrname))
   class Meta:
      db_table = 'usr'
      verbose_name = 'User'

class UsrPermMap(models.Model):
   usr_id = models.ForeignKey(User, db_column='usr')
   perm_id = models.ForeignKey(PermList, db_column='perm')
   depth_id = models.ForeignKey(OrgUnitType, to_field='depth', db_column='depth')
   grantable = models.BooleanField()
   class Admin:
      search_fields = ['usr_id', 'perm_id']  # we need text fields to search...
   class Meta:
      db_table = 'usr_perm_map'
      verbose_name = 'User Permission'
   def __str__(self):
      return "%s -> %s" % ( str(self.usr_id), str(self.perm_id) )


class Card(models.Model):
   usr_id = models.ForeignKey(User, db_column='usr')
   barcode = models.CharField(blank=False, null=False, maxlength=CHAR_MAXLEN)
   active = models.BooleanField()
   def __str__(self): 
      return self.barcode
   class Meta:
      db_table = 'card'
      verbose_name = 'Card'
"""

   

""" --------------------------------------------------------------
    Actor tables
    -------------------------------------------------------------- """

class OrgUnitType(models.Model):
    name = models.CharField(maxlength=100)
    opac_label = models.CharField(maxlength=100)
    depth = models.IntegerField()
    parent_id = models.ForeignKey('self', null=True, related_name='children', db_column='parent')
    can_have_vols = models.BooleanField()
    can_have_users = models.BooleanField()
    class Meta:
        db_table = 'org_unit_type'
        verbose_name = _('Organizational Unit Type')
    class Admin:
        list_display = ('name', 'depth')
        list_filter = ['parent_id']
        ordering = ['depth']
    def __str__(self):
        return self.name

class OrgUnitSetting(models.Model):
    org_unit_id = models.ForeignKey('OrgUnit', db_column='org_unit')
    name = models.CharField(maxlength=CHAR_MAXLEN)
    value = models.CharField(maxlength=CHAR_MAXLEN)
    class Admin:
        list_display = ('org_unit_id', 'name', 'value')
        search_fields = ['name', 'value']
        list_filter = ['name', 'org_unit_id']
    class Meta:
        db_table = 'org_unit_setting'
        ordering = ['org_unit_id', 'name']
        verbose_name = _('Organizational Unit Setting')
    def __str__(self):
        return "%s:%s=%s" % (self.org_unit_id.shortname, self.name, self.value)


class OrgAddress(models.Model):
    valid = models.BooleanField()
    org_unit_id = models.ForeignKey('OrgUnit', db_column='org_unit')
    address_type = models.CharField(blank=False, maxlength=CHAR_MAXLEN, default=_('MAILING'))
    street1 = models.CharField(blank=False, maxlength=CHAR_MAXLEN)
    street2 = models.CharField(maxlength=CHAR_MAXLEN)
    city = models.CharField(blank=False, maxlength=CHAR_MAXLEN)
    county = models.CharField(maxlength=CHAR_MAXLEN)
    state = models.CharField(blank=False, maxlength=CHAR_MAXLEN)
    country = models.CharField(blank=False, maxlength=CHAR_MAXLEN)
    post_code = models.CharField(blank=False, maxlength=CHAR_MAXLEN)
    class Admin:
        search_fields = ['street1', 'city', 'post_code']   
        list_filter = ['org_unit_id']
        list_display = ('street1', 'street2', 'city', 'county', 'state', 'post_code')
    class Meta:
        ordering = ['city']
        db_table = 'org_address'
        verbose_name = _('Organizational Unit Address')
    def __str__(self):
        return self.street1+' '+self.city+', '+self.state+' '+self.post_code

class OrgUnit(models.Model):
    parent_ou_id = models.ForeignKey('self', null=True, related_name='children', db_column='parent_ou')
    ou_type_id = models.ForeignKey(OrgUnitType, db_column='ou_type')
    shortname = models.CharField(maxlength=CHAR_MAXLEN)
    name = models.CharField(maxlength=CHAR_MAXLEN)
    email = models.EmailField(null=True, blank=True)
    phone = models.CharField(maxlength=CHAR_MAXLEN, null=True, blank=True)
    opac_visible = models.BooleanField(blank=True)
    ill_address_id = models.ForeignKey(OrgAddress, 
        db_column='ill_address', related_name='ill_addresses', null=True, blank=True)
    holds_address_id = models.ForeignKey(OrgAddress, 
        db_column='holds_address', related_name='holds_addresses', null=True, blank=True)
    mailing_address_id = models.ForeignKey(OrgAddress, 
        db_column='mailing_address', related_name='mailing_addresses', null=True, blank=True)
    billing_address_id = models.ForeignKey(OrgAddress, 
        db_column='billing_address', related_name='billing_addresses', null=True, blank=True)
    class Admin:
        search_fields = ['name', 'shortname']
        list_display = ('shortname', 'name')
    class Meta:
        db_table = 'org_unit'
        ordering = ['shortname']
        verbose_name = _('Organizational Unit')
    def __str__(self):
        return self.shortname

class HoursOfOperation(models.Model):
    #choices = tuple([ (datetime.time(i), str(i)) for i in range(0,23) ])
    org_unit = models.ForeignKey('OrgUnit', db_column='id')
    # XXX add better time widget support
    dow_0_open = models.TimeField(_('Monday Open'), null=False, blank=False, default=datetime.time(9))
    dow_0_close = models.TimeField(_('Monday Close'), null=False, blank=False, default=datetime.time(17))
    dow_1_open = models.TimeField(_('Tuesday Open'), null=False, blank=False, default=datetime.time(9))
    dow_1_close = models.TimeField(_('Tuesday Close'), null=False, blank=False, default=datetime.time(17))
    dow_2_open = models.TimeField(_('Wednesday Open'), null=False, blank=False, default=datetime.time(9))
    dow_2_close = models.TimeField(_('Wednesday Close'), null=False, blank=False, default=datetime.time(17))
    dow_3_open = models.TimeField(_('Thursday Open'), null=False, blank=False, default=datetime.time(9))
    dow_3_close = models.TimeField(_('Thursday Close'), null=False, blank=False, default=datetime.time(17))
    dow_4_open = models.TimeField(_('Friday Open'), null=False, blank=False, default=datetime.time(9))
    dow_4_close = models.TimeField(_('Friday Close'), null=False, blank=False, default=datetime.time(17))
    dow_5_open = models.TimeField(_('Saturday Open'), null=False, blank=False, default=datetime.time(9))
    dow_5_close = models.TimeField(_('Saturday Close'), null=False, blank=False, default=datetime.time(17))
    dow_6_open = models.TimeField(_('Sunday Open'), null=False, blank=False, default=datetime.time(9))
    dow_6_close = models.TimeField(_('Sunday Close'), null=False, blank=False, default=datetime.time(17))
    class Admin:
        pass
    class Meta:
        db_table = 'hours_of_operation'
        verbose_name = _('Hours of Operation')
        verbose_name_plural = verbose_name
    def __str__(self):
        return str(self.org_unit)



""" --------------------------------------------------------------
    Config tables
    -------------------------------------------------------------- """

class CircModifier(models.Model):
    code = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    name = models.CharField(maxlength=CHAR_MAXLEN)
    description = models.CharField(maxlength=CHAR_MAXLEN);
    sip2_media_type = models.CharField(maxlength=CHAR_MAXLEN);
    magnetic_media = models.BooleanField()
    class Admin:
        search_fields = ['name','code']
        list_display = ('code','name','description','sip2_media_type','magnetic_media')
    class Meta:
        db_table = 'circ_modifier'
        ordering = ['name']
        verbose_name = _('Circulation Modifier')
    def __str__(self):
        return self.name


class VideoRecordingFormat(models.Model):
    code = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    value = models.CharField(maxlength=CHAR_MAXLEN, help_text=INTERVAL_HELP_TEXT);
    class Admin:
        search_fields = ['value','code']
        list_display = ('value','code')
    class Meta:
        db_table = 'videorecording_format_map'
        ordering = ['code']
        verbose_name = _('Video Recording Format')
    def __str__(self):
        return self.value

class RuleCircDuration(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN)
    extended = models.CharField(maxlength=CHAR_MAXLEN, help_text=INTERVAL_HELP_TEXT);
    normal = models.CharField(maxlength=CHAR_MAXLEN, help_text=INTERVAL_HELP_TEXT);
    shrt = models.CharField(maxlength=CHAR_MAXLEN, help_text=INTERVAL_HELP_TEXT);
    max_renewals = models.IntegerField()
    class Admin:
        search_fields = ['name']
        list_display = ('name','extended','normal','shrt','max_renewals')
    class Meta:
        db_table = 'rule_circ_duration'
        ordering = ['name']
        verbose_name = _('Circ Duration Rule')
    def __str__(self):
        return self.name

class CircMatrixMatchpoint(models.Model):
    active = models.BooleanField(blank=False, default=True)
    org_unit_id = models.ForeignKey(OrgUnit, db_column='org_unit', blank=False)
    grp_id = models.ForeignKey(GrpTree, db_column='grp', blank=False, verbose_name=_("User Group"))
    circ_modifier_id = models.ForeignKey(CircModifier, db_column='circ_modifier', null=True,blank=True)
    marc_type_id = models.ForeignKey('ItemTypeMap', db_column='marc_type', null=True,blank=True)
    marc_form_id = models.ForeignKey('ItemFormMap', db_column='marc_form', null=True,blank=True)
    marc_vr_format_id = models.ForeignKey('VideoRecordingFormat', db_column='marc_vr_format', null=True,blank=True)
    ref_flag = models.BooleanField(null=True)
    usr_age_lower_bound = models.CharField(maxlength=CHAR_MAXLEN, help_text=INTERVAL_HELP_TEXT, null=True, blank=True)
    usr_age_upper_bound = models.CharField(maxlength=CHAR_MAXLEN, help_text=INTERVAL_HELP_TEXT, null=True, blank=True)
    class Admin:
        search_fields = ['grp_id','org_unit_id','circ_modifier_id','marc_type_id','marc_form_id',
            'marc_vr_format_id','usr_age_lower_bound','usr_age_upper_bound']

        list_display = ('grp_id','org_unit_id','circ_modifier_id','marc_type_id','marc_form_id',
            'marc_vr_format_id','ref_flag','usr_age_lower_bound','usr_age_upper_bound')

        list_filter = ['grp_id','org_unit_id','circ_modifier_id','marc_type_id','marc_form_id','marc_vr_format_id']
    class Meta:
        db_table = 'circ_matrix_matchpoint'
        ordering = ['id']
        verbose_name = _('Circulation Matrix Matchpoint')
    def __str__(self):
        return _("OrgUnit: %(orgid)s, Group: %(grpid)s, Circ Modifier: %(modid)s") % {
            'orgid':self.org_unit_id, 'grpid':self.grp_id, 'modid':self.circ_modifier_id}

class CircMatrixTest(models.Model):
    matchpoint_id =  models.ForeignKey(CircMatrixMatchpoint, db_column='matchpoint', blank=False, primary_key=True, 
        edit_inline=models.TABULAR, core=True, num_in_admin=1)
    max_items_out = models.IntegerField(null=True, blank=True)
    max_overdue = models.IntegerField(null=True, blank=True)
    max_fines = models.FloatField(max_digits=8, decimal_places=2, null=True, blank=True)
    script_test = models.CharField(maxlength=CHAR_MAXLEN, null=True, blank=True)
    class Admin:
        list_display = ('matchpoint_id','max_items_out','max_overdue','max_fines','script_test')
    class Meta:
        db_table = 'circ_matrix_test'
        ordering = ['matchpoint_id']
        verbose_name = _('Circ Matrix Test')
    def __str__(self):
        return _("%(mid)s, Max Items Out: %(iout)s, Max Overdue: %(odue)s, Max Fines: %(fines)s") % {
            'mid': self.matchpoint_id, 'iout' : self.max_items_out, 'odue':self.max_overdue, 'fines':self.max_fines}

class CircMatrixCircModTest(models.Model):
    matchpoint_id =  models.ForeignKey(CircMatrixMatchpoint, db_column='matchpoint', blank=False, edit_inline=True,core=True, num_in_admin=1)
    items_out = models.IntegerField(blank=False)
    circ_mod_id = models.ForeignKey(CircModifier, db_column='circ_mod', blank=False)
    class Admin:
        search_fields = ['circ_mod_id']
        list_display = ('matchpoint_id','circ_mod_id','items_out')
    class Meta:
        db_table = 'circ_matrix_circ_mod_test'
        ordering = ['matchpoint_id']
        verbose_name = _('Circ Matrix Items Out Cirulation Modifier Subtest')
    def __str__(self):
        return _("%(mid)s, Restriction: %(mod)s") % {'mid': self.matchpoint_id,'mod':self.circ_mod_id}

class CircMatrixRuleSet(models.Model):
    matchpoint_id =  models.ForeignKey(CircMatrixMatchpoint, db_column='matchpoint', 
        blank=False, primary_key=True, edit_inline=True,core=True, num_in_admin=1)
    duration_rule_id = models.ForeignKey(RuleCircDuration, db_column='duration_rule', blank=False)
    recurring_fine_rule_id = models.ForeignKey('RuleRecurringFine', db_column='recurring_fine_rule', blank=False)
    max_fine_rule_id = models.ForeignKey('RuleMaxFine', db_column='max_fine_rule', blank=False)
    class Admin:
        search_fields = ['matchoint_id']
        list_display = ('matchpoint_id','duration_rule_id','recurring_fine_rule_id','max_fine_rule_id')
    class Meta:
        db_table = 'circ_matrix_ruleset'
        ordering = ['matchpoint_id']
        verbose_name = _('Circ Matrix Rule Set')
    def __str__(self):
        return _("Duration: %(dur)s, Recurring Fine: %(rfine)s, Max Fine: %(mfine)s") % {
            'dur':self.duration_rule_id, 'rfine':self.recurring_fine_rule_id, 'mfine':self.max_fine_rule_id}

class RuleMaxFine(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN)
    amount = models.FloatField(max_digits=6, decimal_places=2)
    class Admin:
        search_fields = ['name']
        list_display = ('name','amount')
    class Meta:
        db_table = 'rule_max_fine'
        ordering = ['name']
        verbose_name = _('Circ Max Fine Rule')
    def __str__(self):
        return self.name

class RuleRecurringFine(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN)
    high = models.FloatField(max_digits=6, decimal_places=2)
    normal = models.FloatField(max_digits=6, decimal_places=2)
    low = models.FloatField(max_digits=6, decimal_places=2)
    class Admin:
        search_fields = ['name']
        list_display = ('name','high', 'normal', 'low')
    class Meta:
        db_table = 'rule_recuring_fine'
        ordering = ['name']
        verbose_name = 'Circ Recurring Fine Rule'
    def __str__(self):
        return self.name

class IdentificationType(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN)
    class Admin:
        search_fields = ['name']
    class Meta:
        db_table = 'identification_type'
        ordering = ['name']
        verbose_name = _('Identification Type')
    def __str__(self):
        return self.name


class RuleAgeHoldProtect(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN)
    age = models.CharField(blank=True, maxlength=100, help_text=INTERVAL_HELP_TEXT)
    prox = models.IntegerField()
    class Admin:
        search_fields = ['name']
    class Meta:
        db_table = 'rule_age_hold_protect'
        ordering = ['name']
        verbose_name = _('Hold Age Protection Rule')
    def __str__(self):
        return self.name



class MetabibField(models.Model):
    field_class_choices = (
        ('title', 'Title'),
        ('author', 'Author'),
        ('subject', 'Subject'),
        ('series', 'Series'),
        ('keyword', 'Keyword'),
    )
    field_class = models.CharField(maxlength=CHAR_MAXLEN, choices=field_class_choices, null=False, blank=False)
    name = models.CharField(maxlength=CHAR_MAXLEN, null=False, blank=False)
    xpath = models.TextField(null=False, blank=False)
    weight = models.IntegerField(null=False, blank=False)
    format_id = models.ForeignKey('XmlTransform', db_column='format')
    class Admin:
        search_fields = ['name', 'field_class', 'format_id']
        list_display = ('field_class', 'name', 'format_id')
    class Meta:
        db_table = 'metabib_field'
        ordering = ['field_class', 'name']
        verbose_name = _('Metabib Field')
    def __str__(self):
        return self.name


class CopyStatus(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN)
    holdable = models.BooleanField()
    class Admin:
        search_fields = ['name']
        list_display = ('name', 'holdable')
    class Meta:
        db_table = 'copy_status'
        ordering = ['name']
        verbose_name= _('Copy Status')
        verbose_name_plural= _('Copy Statuses')
    def __str__(self):
        return self.name


class AudienceMap(models.Model):
    code = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    value = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    description = models.CharField(maxlength=CHAR_MAXLEN)
    class Admin:
        search_fields = ['code', 'value', 'description']
        list_display = ('code', 'value', 'description')
    class Meta:
        db_table = 'audience_map'
        ordering = ['code']
        verbose_name = _('Audience Map')
    def __str__(self):
        return self.code


class BibSource(models.Model):
    quality = models.IntegerField()
    source = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    transcendant = models.BooleanField()
    class Admin:
        search_fields = ['source']
        list_display = ('source', 'quality', 'transcendant')
    class Meta:
        db_table = 'bib_source'
        ordering = ['source']
        verbose_name = _('Bib Source')
    def __str__(self):
        return self.source

class ItemFormMap(models.Model):
    code = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    value = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    class Admin:
        search_fields = ['code', 'value']
        list_display = ('code', 'value')
    class Meta:
        db_table = 'item_form_map'
        ordering = ['code']
        verbose_name = _('Item Form Map')
    def __str__(self):
        return self.code

class ItemTypeMap(models.Model):
    code = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    value = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    class Admin:
        search_fields = ['code', 'value']
        list_display = ('code', 'value')
    class Meta:
        db_table = 'item_type_map'
        ordering = ['code']
        verbose_name = _('Item Type Map')
    def __str__(self):
        return self.code



class LanguageMap(models.Model):
    code = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    value = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    class Admin:
        search_fields = ['code', 'value']
        list_display = ('code', 'value')
    class Meta:
        db_table = 'language_map'
        ordering = ['code']
        verbose_name = _('Language Map')
    def __str__(self):
        return self.code


class LitFormMap(models.Model):
    code = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    value = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    description = models.CharField(maxlength=CHAR_MAXLEN)
    class Admin:
        search_fields = ['code', 'value', 'description']
        list_display = ('code', 'value', 'description')
    class Meta:
        db_table = 'lit_form_map'
        ordering = ['code']
        verbose_name = _('Lit Form Map')
    def __str__(self):
        return self.code

class NetAccessLevel(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    class Admin:
        search_fields = ['name']
    class Meta:
        db_table = 'net_access_level'
        ordering = ['name']
        verbose_name = _('Net Access Level')
    def __str__(self):
        return self.name


class XmlTransform(models.Model):
    name = models.CharField(maxlength=CHAR_MAXLEN, blank=False, primary_key=True)
    namespace_uri = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    prefix = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    xslt = models.CharField(maxlength=CHAR_MAXLEN, blank=False)
    class Admin:
        search_fields = ['name', 'namespace_uri', 'prefix' ]
        list_display = ('name', 'prefix', 'namespace_uri', 'xslt')
    class Meta:
        db_table = 'xml_transform'
        ordering = ['name']
        verbose_name = _('XML Transform')
    def __str__(self):
        return self.name





