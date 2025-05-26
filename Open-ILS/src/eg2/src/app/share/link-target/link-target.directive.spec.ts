import { Component, DebugElement } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { By } from '@angular/platform-browser';
import { LinkTargetDirective } from './link-target.directive';
import { LinkTargetService } from './link-target.service';
import { BehaviorSubject } from 'rxjs';

interface FixtureContext {
    fixture: ComponentFixture<TestComponent>;
    elSameTab: HTMLAnchorElement;
    elNewTab: HTMLAnchorElement;
}

const NEW_TAB_DESCRIBER_ID = 'link-opens-newtab';

@Component({
    template: `
        <a id="same-tab" href="#" target="_self">Same Tab Link</a>
        <a id="new-tab" href="#" target="_blank">New Tab Link</a>
    `
})
class TestComponent {}

function createFixtureContext(initialSetting: boolean): FixtureContext {
    const setting$ = new BehaviorSubject<boolean>(initialSetting);
    const service = jasmine.createSpyObj<LinkTargetService>([], {
        newTabsDisabled$: setting$.asObservable()
    });

    TestBed.configureTestingModule({
        declarations: [TestComponent, LinkTargetDirective],
        providers: [
            { provide: LinkTargetService, useValue: service }
        ]
    });

    const fixture = TestBed.createComponent(TestComponent);
    fixture.detectChanges();

    return {
        fixture,
        elSameTab: fixture.debugElement.query(By.css('#same-tab'))
            .nativeElement as HTMLAnchorElement,
        elNewTab: fixture.debugElement.query(By.css('#new-tab'))
            .nativeElement as HTMLAnchorElement
    };
}

describe('LinkTargetDirective', () => {
    let elSameTab: HTMLAnchorElement;
    let elNewTab: HTMLAnchorElement;

    describe('when new tabs are not disabled', () => {
        beforeEach(() => {
            ({ elSameTab, elNewTab } = createFixtureContext(false));
        });

        it('should keep the original target', () => {
            expect(elSameTab.getAttribute('target')).toBe('_self');
            expect(elNewTab.getAttribute('target')).toBe('_blank');
        });

        it(`should add ${NEW_TAB_DESCRIBER_ID} for new-tab links`, () => {
            expect(elNewTab.getAttribute('aria-describedby'))
                .toBe(NEW_TAB_DESCRIBER_ID);
        });

        it(`should not add ${NEW_TAB_DESCRIBER_ID} for same-tab links`, () => {
            expect(elSameTab.getAttribute('aria-describedby')).toBeNull();
        });
    });

    describe('when new tabs are disabled', () => {
        beforeEach(() => {
            ({ elSameTab, elNewTab } = createFixtureContext(true));
        });

        it('should remove the target for new-tab links', () => {
            expect(elNewTab.getAttribute('target')).toBeNull();
        });

        it (`should not add ${NEW_TAB_DESCRIBER_ID} for new-tab links`, () => {
            expect(elNewTab.getAttribute('aria-describedby')).toBeNull();
        });

        it('should not change the target for same-tab links', () => {
            expect(elSameTab.getAttribute('target')).toBe('_self');
        });
    });
});
