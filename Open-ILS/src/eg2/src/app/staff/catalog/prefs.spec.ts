import { ServerStoreService } from '@eg/core/server-store.service';
import { PreferencesComponent } from './prefs.component';
import { ToastService } from '@eg/share/toast/toast.service';
import { StaffCatalogService } from './catalog.service';

let component: PreferencesComponent;
const mockToast = jasmine.createSpyObj<ToastService>(['success']);
const mockStaffCat = jasmine.createSpyObj<StaffCatalogService>(['createContext']);
const mockStore = jasmine.createSpyObj<ServerStoreService>(['getItemBatch']);

describe('prefs.component', () => {
    describe('#showCoursePreferences', () => {
        it('when work_ou is using the course module', async () => {
            mockStore.getItemBatch.and.returnValue(Promise.resolve({'circ.course_materials_opt_in': true}));
            component = new PreferencesComponent(mockStore, mockToast, mockStaffCat, null);
            await component.ngOnInit();
            expect(component.showCoursePreferences()).toBe(true);
        });
        it('when work_ou is not using the course module', async () => {
            mockStore.getItemBatch.and.returnValue(Promise.resolve({'circ.course_materials_opt_in': false}));
            component = new PreferencesComponent(mockStore, mockToast, mockStaffCat, null);
            await component.ngOnInit();
            expect(component.showCoursePreferences()).toBe(false);
        });
    });
});
