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

@Component({selector: 'eg-grid'})
class MockGridComponent {
    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onRowActivate = new EventEmitter();
}

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
            declarations: [ CourseListComponent, MockGridComponent ],
            schemas: [ CUSTOM_ELEMENTS_SCHEMA ],
            imports: [NgbNavModule],
            providers: [
                { provide: CourseService, useValue: {}},
                { provide: AuthService, useValue: MockGenerators.authService() },
                { provide: IdlService, useValue: MockGenerators.idlService({}) },
                { provide: OrgService, useValue: {} },
                { provide: PcrudService, useValue: {} },
                { provide: ToastService, useValue: {} },
                { provide: Router, useValue: router},
                { provide: WINDOW, useValue: window }
            ]
        }).compileComponents();
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
