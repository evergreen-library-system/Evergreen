import {ComponentFixture, TestBed} from '@angular/core/testing';
import {DebugElement} from '@angular/core';
import {By} from '@angular/platform-browser';
import {OrgFamilySelectComponent} from './org-family-select.component';
import {ReactiveFormsModule} from '@angular/forms';
import {CookieService} from 'ngx-cookie';
import {OrgService} from '@eg/core/org.service';
import { OrgSelectComponent } from '../org-select/org-select.component';
import { MockOrgSelectComponent } from 'test_data/mock-components';


describe('Component: OrgFamilySelect', () => {
    let component: OrgFamilySelectComponent;
    let fixture: ComponentFixture<OrgFamilySelectComponent>;
    let includeAncestors: DebugElement;
    let includeDescendants: DebugElement;
    let orgServiceStub: Partial<OrgService>;
    let cookieServiceStub: Partial<CookieService>;

    beforeEach(() => {
        // stub of OrgService for testing
        // with a super simple org structure:
        // 1 is the root note, with no children
        orgServiceStub = {
            root: () => {
                return {
                    a: [],
                    classname: 'aou',
                    _isfieldmapper: true,
                    shortname: () => 'ROOT',
                    name: () => 'My Root',
                    id: () => 1};
            },
            get: (ouId: number) => {
                return {
                    a: [],
                    classname: 'aou',
                    _isfieldmapper: true,
                    shortname: () => 'LIB',
                    name: () => 'My Library',
                    children: () => Array() };
            }
        };
        cookieServiceStub = {};
        TestBed.configureTestingModule({
            imports: [
                MockOrgSelectComponent,
                OrgFamilySelectComponent,
                ReactiveFormsModule,
            ], providers: [
                { provide: CookieService, useValue: cookieServiceStub },
                { provide: OrgService, useValue: orgServiceStub},
            ]}).overrideComponent(OrgFamilySelectComponent, {
            remove: {imports: [OrgSelectComponent]},
            add: {imports: [MockOrgSelectComponent]}
        });
        fixture = TestBed.createComponent(OrgFamilySelectComponent);
        component = fixture.componentInstance;
        component.domId = 'family-test';
        component.selectedOrgId = 1;
        fixture.detectChanges();
    });


    it('provides includeAncestors checkbox by default', () => {
        includeAncestors = fixture.debugElement.query(By.css('#family-test-include-ancestors'));
        expect(includeAncestors.nativeElement).toBeTruthy();
    });

    it('provides includeDescendants checkbox by default', () => {
        includeDescendants = fixture.debugElement.query(By.css('#family-test-include-descendants'));
        expect(includeDescendants.nativeElement).toBeTruthy();
    });

    it('allows user to turn off includeAncestors checkbox', () => {
        component.hideAncestorSelector = true;
        fixture.detectChanges();
        includeAncestors = fixture.debugElement.query(By.css('#family-test-include-ancestors'));
        expect(includeAncestors).toBeNull();
    });

    it('allows user to turn off includeDescendants checkbox', () => {
        component.hideDescendantSelector = true;
        fixture.detectChanges();
        includeDescendants = fixture.debugElement.query(By.css('#family-test-include-descendants'));
        expect(includeDescendants).toBeNull();
    });

    it('disables includeAncestors checkbox when root OU is chosen', () => {
        fixture.detectChanges();
        includeAncestors = fixture.debugElement.query(By.css('#family-test-include-ancestors'));
        expect(includeAncestors.nativeElement.disabled).toBe(true);
    });

    it('disables includeAncestors checkbox when OU has no children', () => {
        fixture.detectChanges();
        includeDescendants = fixture.debugElement.query(By.css('#family-test-include-descendants'));
        expect(includeDescendants.nativeElement.disabled).toBe(true);
    });

});

