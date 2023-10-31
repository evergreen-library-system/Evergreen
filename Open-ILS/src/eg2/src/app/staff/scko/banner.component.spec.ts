import { SckoBannerComponent } from "./banner.component";
import { SckoService } from "./scko.service";

const mockSckoService = jasmine.createSpyObj<SckoService>(['resetPatronTimeout', 'checkout']);
describe('banner component', () => {
  describe('item barcode', () => {
    it('resets its value upon form submission', () => {
        const component = new SckoBannerComponent(null, null, null, null, null, null, mockSckoService);
        component.itemBarcode = 'ABC123';
        component.submitItemBarcode();
        expect(component.itemBarcode).toEqual('');
    });
  });
});
