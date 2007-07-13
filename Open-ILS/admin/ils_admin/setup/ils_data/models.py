from django.db import models
from django.db.models import signals
from django.dispatch import dispatcher

INTERVAL_HELP_TEXT = _('examples: "1 hour", "14 days", "3 months", "DD:HH:MM:SS.ms"')
CHAR_MAXLEN=200 # just provide a sane default


""" --------------------------------------------------------------
    Permission tables
    -------------------------------------------------------------- """

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

class PermList(models.Model):
    code = models.CharField(maxlength=100)
    description = models.CharField(blank=True, maxlength=CHAR_MAXLEN)
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
    grp_id = models.ForeignKey(GrpTree, db_column='grp')
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



""" --------------------------------------------------------------
    Config tables
    -------------------------------------------------------------- """

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





