import { TestBed } from '@angular/core/testing';
import { CourseListComponent, WINDOW } from './course-list.component';
import { CourseService } from '@eg/staff/share/course.service';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { Router } from '@angular/router';
import { MockGenerators } from 'test_data/mock_generators';
import { ToastService } from '@eg/share/toast/toast.service';
import { Component, CUSTOM_ELEMENTS_SCHEMA, EventEmitter, Output } from '@angular/core';
import { NgbNavModule } from '@ng-bootstrap/ng-bootstrap';
import { FormatService } from '@eg/core/format.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { LocaleService } from '@eg/core/locale.service';
import { StringService } from '@eg/share/string/string.service';
import { FmRecordEditorComponent } from '@eg/share/fm-editor/fm-editor.component';
import { OrgFamilySelectComponent } from '@eg/share/org-family-select/org-family-select.component';

@Component({selector: 'eg-grid'})
class MockGridComponent {
    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onRowActivate = new EventEmitter();
}

@Component({selector: 'eg-org-family-select'})
class MockOrgFamilySelectComponent {}

describe('CourseListComponent', () => {
    let component: CourseListComponent;
    let router;
    let window;

    beforeEach(async () => {
        router = jasmine.createSpyObj<Router>(['navigate'], {url: '/staff/admin/local/asset/course_list'});
        const mockLocation = jasmine.createSpyObj<Location>([], {
            href: 'https://my-evergreen.com/eg2/en-US/staff/admin/local/asset/course_list'
        });
        window = jasmine.createSpyObj<Window>(['open'], {location: mockLocation});
        TestBed.configureTestingModule({
            imports: [CourseListComponent],
            providers: [
                { provide: CourseService, useValue: {}},
                { provide: AuthService, useValue: MockGenerators.authService() },
                { provide: IdlService, useValue: MockGenerators.idlService({}) },
                { provide: OrgService, useValue: {} },
                { provide: PcrudService, useValue: {} },
                { provide: ToastService, useValue: {} },
                { provide: Router, useValue: router},
                { provide: WINDOW, useValue: window },
                { provide: FormatService, useValue: {} },
                { provide: LocaleService, useValue: {} },
                { provide: StringService, useValue: {}}
            ]
        }).compileComponents();
        TestBed.overrideComponent(CourseListComponent, {
            remove: {imports: [StaffCommonModule, FmRecordEditorComponent, OrgFamilySelectComponent]},
            add: {imports: [MockGridComponent, MockOrgFamilySelectComponent, NgbNavModule], schemas: [CUSTOM_ELEMENTS_SCHEMA]}
        });
        const fixture = TestBed.createComponent(CourseListComponent);
        component = fixture.componentInstance;
        await fixture.detectChanges();
    });
    it('can navigate to the correct page', () => {
        component.editSelected([MockGenerators.idlObject({id: 20})]);
        expect(router.navigate).toHaveBeenCalledOnceWith(['/staff/admin/local/asset/course_list/20']);
    });
    it('can navigate to several pages', () => {
        component.editSelected([MockGenerators.idlObject({id: 20}), MockGenerators.idlObject({id: 21})]);
        expect(window.open).toHaveBeenCalledWith('https://my-evergreen.com/eg2/en-US/staff/admin/local/asset/course_list/20', 'course-20');
        expect(window.open).toHaveBeenCalledWith('https://my-evergreen.com/eg2/en-US/staff/admin/local/asset/course_list/21', 'course-21');
    });
});
