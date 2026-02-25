import { ServerStoreService } from '@eg/core/server-store.service';
import { PreferencesComponent } from './prefs.component';
import { ToastService } from '@eg/share/toast/toast.service';
import { StaffCatalogService } from './catalog.service';
import { TestBed } from '@angular/core/testing';
import { CatalogService } from '@eg/share/catalog/catalog.service';
import { ActivatedRoute } from '@angular/router';
import { SearchFormComponent } from './search-form.component';
import { SortOrderSelectComponent } from './sort-order-select/sort-order-select.component';
import { StaffCommonModule } from '../common.module';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';

let component: PreferencesComponent;
const mockToast = jasmine.createSpyObj<ToastService>(['success']);
const mockStaffCat = jasmine.createSpyObj<StaffCatalogService>(['createContext']);
const mockStore = jasmine.createSpyObj<ServerStoreService>(['getItemBatch']);

function createPreferencesComponent(store: ServerStoreService): PreferencesComponent {
    TestBed.configureTestingModule({providers: [
        {provide: ServerStoreService, useValue: store},
        {provide: ToastService, useValue: mockToast},
        {provide: StaffCatalogService, useValue: mockStaffCat},
        {provide: CatalogService, useValue: null},
        {provide: ActivatedRoute, useValue: null}
    ]});
    TestBed.overrideComponent(PreferencesComponent, {
        add: {schemas: [CUSTOM_ELEMENTS_SCHEMA]},
        remove: {imports: [SearchFormComponent,
            SortOrderSelectComponent,
            StaffCommonModule]}
    });
    return TestBed.createComponent(PreferencesComponent).componentInstance;
}

describe('prefs.component', () => {
    describe('#showCoursePreferences', () => {
        it('when work_ou is using the course module', async () => {
            mockStore.getItemBatch.and.returnValue(Promise.resolve({'circ.course_materials_opt_in': true}));
            component = createPreferencesComponent(mockStore);
            await component.ngOnInit();
            console.log(component['settings']);
            expect(component.showCoursePreferences()).toBe(true);
        });
        it('when work_ou is not using the course module', async () => {
            mockStore.getItemBatch.and.returnValue(Promise.resolve({'circ.course_materials_opt_in': false}));
            component = createPreferencesComponent(mockStore);
            await component.ngOnInit();
            expect(component.showCoursePreferences()).toBe(false);
        });
    });
});
