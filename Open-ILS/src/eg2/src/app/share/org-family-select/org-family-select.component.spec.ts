import {ComponentFixture, TestBed} from '@angular/core/testing';
import {Component, DebugElement, Input} from '@angular/core';
import {By} from '@angular/platform-browser';
import {OrgFamilySelectComponent} from './org-family-select.component';
import {ReactiveFormsModule} from '@angular/forms';
import {CookieService} from 'ngx-cookie';
import {OrgService} from '@eg/core/org.service';

@Component({
    selector: 'eg-org-select',
    template: ''
})
class MockOrgSelectComponent {
    @Input() disabled?: boolean;
    @Input() domId: string;
    @Input() limitPerms: string;
    @Input() ariaLabel?: string;
    @Input() applyOrgId(id: number) {}
}

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
                    id: () => 1};
            },
            get: (ouId: number) => {
                return {
                    a: [],
                    classname: 'aou',
                    _isfieldmapper: true,
                    children: () => Array() };
            }
        };
        cookieServiceStub = {};
        TestBed.configureTestingModule({
            imports: [
                ReactiveFormsModule,
            ], providers: [
                { provide: CookieService, useValue: cookieServiceStub },
                { provide: OrgService, useValue: orgServiceStub},
            ], declarations: [
                OrgFamilySelectComponent,
                MockOrgSelectComponent,
            ]});
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

