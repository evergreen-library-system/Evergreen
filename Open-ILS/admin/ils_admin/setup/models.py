from django.db import models
from django.db.models import signals
from django.dispatch import dispatcher

# Create your models here.

INTERVAL_HELP_TEXT = 'examples: "1 hour", "14 days", "3 months", "DD:HH:MM:SS.ms"'
PG_SCHEMAS = "actor, permission, public, config"


# ---------------------------------------------------------------------
# Here we run some SQL to manually set the postgres schema search-paths
# ---------------------------------------------------------------------
def setSearchPath():
   from django.db import connection
   cursor = connection.cursor()
   print "SET search_path TO %s" % PG_SCHEMAS
   cursor.execute("SET search_path TO %s" % PG_SCHEMAS)
dispatcher.connect(setSearchPath, signal=signals.class_prepared)
dispatcher.connect(setSearchPath, signal=signals.pre_init)


class GrpTree(models.Model):
   name = models.CharField(maxlength=100)
   parent_id = models.ForeignKey('self', null=True, related_name='children', db_column='parent')
   description = models.CharField(blank=True, maxlength=200)
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
      verbose_name = 'User Group'
   def __str__(self):
      return self.name

class OrgUnitType(models.Model):
   name = models.CharField(maxlength=100)
   opac_label = models.CharField(maxlength=100)
   depth = models.IntegerField()
   parent_id = models.ForeignKey('self', null=True, related_name='children', db_column='parent')
   can_have_vols = models.BooleanField()
   can_have_users = models.BooleanField()
   class Meta:
      db_table = 'org_unit_type'
      verbose_name = 'Library Type'
   class Admin:
      list_display = ('name', 'depth')
      list_filter = ['parent_id']
      ordering = ['depth']
   def __str__(self):
      return self.name

class PermList(models.Model):
   code = models.CharField(maxlength=100)
   description = models.CharField(blank=True, maxlength=200)
   class Admin:
      list_display = ('code','description')
      search_fields = ['code']
   class Meta:
      db_table = 'perm_list'
      ordering = ['code']
      verbose_name = 'Permission'
   def __str__(self):
      return self.code

class GrpPermMap(models.Model):
   grp_id = models.ForeignKey(GrpTree, db_column='grp')
   perm_id = models.ForeignKey(PermList, db_column='perm')
   depth_id = models.ForeignKey(OrgUnitType, to_field='depth', db_column='depth')
   grantable = models.BooleanField()
   class Admin:
      list_filter = ['grp_id']
      list_display = ('perm_id', 'grp_id', 'depth_id')
   class Meta:
      db_table = 'grp_perm_map'
      ordering = ['perm_id', 'grp_id']
      verbose_name = 'Permission Setting'
   def __str__(self):
      return str(self.grp_id)+' -> '+str(self.perm_id)



""" There's no way to do user-based mangling given the size of the data without custom handling.

class User(models.Model):
   card_id = models.ForeignKey('Card', db_column='card')
   profile_id = models.ForeignKey(GrpTree, db_column='profile')
   usrname = models.CharField(blank=False, null=False, maxlength=200)
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
   barcode = models.CharField(blank=False, null=False, maxlength=200)
   active = models.BooleanField()
   def __str__(self): 
      return self.barcode
   class Meta:
      db_table = 'card'
      verbose_name = 'Card'
"""

   


class OrgAddress(models.Model):
   valid = models.BooleanField()
   org_unit_id = models.ForeignKey('OrgUnit', db_column='org_unit')
   address_type = models.CharField(blank=False, maxlength=200, default='MAILING')
   street1 = models.CharField(blank=False, maxlength=200)
   street2 = models.CharField(maxlength=200)
   city = models.CharField(blank=False, maxlength=200)
   county = models.CharField(maxlength=200)
   state = models.CharField(blank=False, maxlength=200)
   country = models.CharField(blank=False, maxlength=200)
   post_code = models.CharField(blank=False, maxlength=200)
   class Admin:
      search_fields = ['street1', 'city', 'post_code']   
      list_filter = ['org_unit_id']
      list_display = ('street1', 'street2', 'city', 'county', 'state', 'post_code')
   class Meta:
      ordering = ['city']
      db_table = 'org_address'
      verbose_name = 'Library Address'
   def __str__(self):
      return self.street1+' '+self.city+', '+self.state+' '+self.post_code

class OrgUnit(models.Model):
   parent_ou_id = models.ForeignKey('self', null=True, related_name='children', db_column='parent_ou')
   ou_type_id = models.ForeignKey(OrgUnitType, db_column='ou_type')
   shortname = models.CharField(maxlength=200)
   name = models.CharField(maxlength=200)
   email = models.EmailField(null=True, blank=True)
   phone = models.CharField(maxlength=200, null=True, blank=True)
   opac_visible = models.BooleanField(blank=True)
   ill_address_id = models.ForeignKey(OrgAddress, db_column='ill_address', null=True, blank=True)
   holds_address_id = models.ForeignKey(OrgAddress, db_column='holds_address', null=True, blank=True)
   mailing_address_id = models.ForeignKey(OrgAddress, db_column='mailing_address', null=True, blank=True)
   billing_address_id = models.ForeignKey(OrgAddress, db_column='billing_address', null=True, blank=True)
   class Admin:
      search_fields = ['name', 'shortname']
      #list_filter = ['parent_ou_id'] # works, but shows all libs as options, so ruins the point
      list_display = ('shortname', 'name')
   class Meta:
      db_table = 'org_unit'
      ordering = ['shortname']
      verbose_name = 'Library'
   def __str__(self):
      return self.shortname


class RuleCircDuration(models.Model):
   name = models.CharField(maxlength=200)
   extended = models.CharField(maxlength=200, help_text=INTERVAL_HELP_TEXT);
   normal = models.CharField(maxlength=200, help_text=INTERVAL_HELP_TEXT);
   shrt = models.CharField(maxlength=200, help_text=INTERVAL_HELP_TEXT);
   max_renewals = models.IntegerField()
   class Admin:
      search_fields = ['name']
      list_display = ('name','extended','normal','shrt','max_renewals')
   class Meta:
      db_table = 'rule_circ_duration'
      ordering = ['name']
      verbose_name = 'Circ Duration Rule'
   def __str__(self):
      return self.name


class RuleMaxFine(models.Model):
   name = models.CharField(maxlength=200)
   amount = models.FloatField(max_digits=6, decimal_places=2)
   class Admin:
      search_fields = ['name']
      list_display = ('name','amount')
   class Meta:
      db_table = 'rule_max_fine'
      ordering = ['name']
      verbose_name = 'Circ Max Fine Rule'
   def __str__(self):
      return self.name

class RuleRecurringFine(models.Model):
   name = models.CharField(maxlength=200)
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
   name = models.CharField(maxlength=200)
   class Admin:
      search_fields = ['name']
   class Meta:
      db_table = 'identification_type'
      ordering = ['name']
      verbose_name = 'Identification Type'
   def __str__(self):
      return self.name


class RuleAgeHoldProtect(models.Model):
   name = models.CharField(maxlength=200)
   age = models.CharField(blank=True, maxlength=100, help_text=INTERVAL_HELP_TEXT)
   prox = models.IntegerField()
   class Admin:
      search_fields = ['name']
   class Meta:
      db_table = 'rule_age_hold_protect'
      ordering = ['name']
      verbose_name = 'Hold Age Protection Rule'
   def __str__(self):
      return self.name

