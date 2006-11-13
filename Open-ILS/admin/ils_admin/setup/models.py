from django.db import models

# Create your models here.

class GrpTree(models.Model):
	name = models.CharField(maxlength=100)
	parent_id = models.ForeignKey('self', null=True, related_name='children', db_column='parent')
	description = models.CharField(blank=True, maxlength=200)
	perm_interval = models.CharField(blank=True, maxlength=100)
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
		search_fields = ['grp_id', 'perm_id']
		list_display = ('grp_id', 'perm_id')
	class Meta:
		db_table = 'grp_perm_map'
		ordering = ['grp_id']
		verbose_name = 'Permission Setting'
	def __str__(self):
		return str(self.grp_id)+' -> '+str(self.perm_id)


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
	ill_address_id = models.ForeignKey(OrgAddress, db_column='ill_address', null=True, blank=True)
	holds_address_id = models.ForeignKey(OrgAddress, db_column='holds_address', null=True, blank=True)
	mailing_address_id = models.ForeignKey(OrgAddress, db_column='mailing_address', null=True, blank=True)
	billing_address_id = models.ForeignKey(OrgAddress, db_column='billing_address', null=True, blank=True)
	class Admin:
		search_fields = ['name', 'shortname']
		#list_filter = ['parent_ou_id']
		list_display = ('shortname', 'name')
	class Meta:
		db_table = 'org_unit'
		ordering = ['shortname']
		verbose_name = 'Library'
	def __str__(self):
		return self.shortname




