import { OrgService } from "@eg/core/org.service";
import { SckoBannerComponent } from "./banner.component";
import { SckoService } from "./scko.service";
import { AuthService } from "@eg/core/auth.service";
import { ForceReloadService } from "@eg/share/util/force-reload.service";

const mockSckoService = jasmine.createSpyObj<SckoService>(['resetPatronTimeout', 'checkout']);
const mockOrgService = jasmine.createSpyObj<OrgService>(['clearCachedSettings', 'settings', 'root']);
const mockAuthService = jasmine.createSpyObj<AuthService>(['login', 'logout']);
const mockForceReload = jasmine.createSpyObj<ForceReloadService>(['reload']);
const rootOrgUnit = { id: () => 1, a: null, classname: 'aou', _isfieldmapper: null };
window.location

mockOrgService.root.and.returnValue(rootOrgUnit);
mockOrgService.clearCachedSettings.and.returnValue(Promise.resolve());
mockAuthService.login.and.returnValue(Promise.resolve());

let component = new SckoBannerComponent(null, null, mockAuthService, mockOrgService, null, mockSckoService, mockForceReload);

describe('banner component', () => {
  describe('item barcode', () => {
    it('resets its value upon form submission', () => {
        component.itemBarcode = 'ABC123';
        component.submitItemBarcode();
        expect(component.itemBarcode).toEqual('');
    });
  });
  describe('submitStaffLogin', () => {
    it('fails if no workstation and the root OU requires a workstation', async () => {
      mockOrgService.settings.and.returnValue(Promise.resolve({'circ.selfcheck.workstation_required': true}))
      component = new SckoBannerComponent(null, null, mockAuthService, mockOrgService, null, mockSckoService, mockForceReload);
      component.staffUsername = 'user1';
      component.staffPassword = 'password123';
      await component.submitStaffLogin();
      expect(component.staffLoginFailed).toBe(true);
      expect(component.missingRequiredWorkstation).toBe(true);
    });
    it('succeeds if no workstation but the root OU does not require a workstation', async () => {
      mockOrgService.settings.and.returnValue(Promise.resolve({'circ.selfcheck.workstation_required': false}))
      component = new SckoBannerComponent(null, null, mockAuthService, mockOrgService, null, mockSckoService, mockForceReload);
      component.staffUsername = 'user1';
      component.staffPassword = 'password123';
      await component.submitStaffLogin();
      expect(component.staffLoginFailed).toBe(false);
      expect(component.missingRequiredWorkstation).toBe(false);
    });
  });
});
