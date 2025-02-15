import { ComponentFixture, fakeAsync, TestBed, tick } from '@angular/core/testing';
import { ExpandableListComponent } from './expandable-list.component';
import { provideRouter } from '@angular/router';

describe('ExpandableListComponent', () => {
    let component: ExpandableListComponent;
    let fixture: ComponentFixture<ExpandableListComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ ExpandableListComponent ],
            providers: [provideRouter([])]
        })
            .compileComponents();

        fixture = TestBed.createComponent(ExpandableListComponent);
        component = fixture.componentInstance;
        component.entries = [
            {text: 'Espeon'},
            {text: 'Flareon'},
            {text: 'Glaceon'},
            {text: 'Leafeon'},
            {text: 'Umbreon'}
        ];
        component.entryLimit = 3;
        fixture.detectChanges();
    });

    it('begins as collapsed', () => {
        const listItems = fixture.nativeElement.querySelectorAll('li');
        expect(listItems.length).toEqual(4); // three entries plus a "More" button
        expect(listItems[0].textContent).toEqual('Espeon');
        expect(listItems[1].textContent).toEqual('Flareon');
        expect(listItems[2].textContent).toEqual('Glaceon');

        expect(listItems[3].querySelector('button')).toBeTruthy();
        expect(listItems[3].textContent).toContain('Read more');
    });

    it('can be expanded', () => {
        fixture.nativeElement.querySelector('button').click();
        fixture.detectChanges();

        const listItems = fixture.nativeElement.querySelectorAll('li');
        expect(listItems.length).toEqual(6); // all five entries plus a "Less" button
        expect(listItems[0].textContent).toEqual('Espeon');
        expect(listItems[1].textContent).toEqual('Flareon');
        expect(listItems[2].textContent).toEqual('Glaceon');
        expect(listItems[3].textContent).toEqual('Leafeon');
        expect(listItems[4].textContent).toEqual('Umbreon');

        expect(listItems[5].querySelector('button')).toBeTruthy();
        expect(listItems[5].textContent).toContain('Read less');
    });

    it('sets focus on the content half a second after click', fakeAsync(() => {
        fixture.nativeElement.querySelector('button').click();
        fixture.detectChanges();
        tick(500);

        expect(document.activeElement.tagName).toEqual('UL');
    }));

    it('shows all entries -- no buttons -- if entry limit is null', () => {
        component.entryLimit = null;
        fixture.detectChanges();

        const listItems = fixture.nativeElement.querySelectorAll('li');
        expect(listItems.length).toEqual(5);
        expect(listItems[0].textContent).toEqual('Espeon');
        expect(listItems[1].textContent).toEqual('Flareon');
        expect(listItems[2].textContent).toEqual('Glaceon');
        expect(listItems[3].textContent).toEqual('Leafeon');
        expect(listItems[4].textContent).toEqual('Umbreon');

        expect(fixture.nativeElement.querySelector('button')).toBeFalsy();
    });

    it('can accept a character limit', () => {
        component.entries = [
            {text: 'Elphaba Thropp'},
            {text: 'Fiyero Tigelaar'},
            {text: 'Glinda Upland'},
            {text: 'Nessarose Thropp'},
        ];
        component.characterLimit = 10;
        fixture.detectChanges();

        expect(fixture.nativeElement.innerText).toContain('Elphaba…');
        expect(fixture.nativeElement.innerText).toContain('Fiyero…');
        expect(fixture.nativeElement.innerText).toContain('Glinda…');

        expect(fixture.nativeElement.innerText).not.toContain('Thropp');
        expect(fixture.nativeElement.innerText).not.toContain('Tigelaar');
        expect(fixture.nativeElement.innerText).not.toContain('Upland');

        component.characterLimit = 50;
        fixture.detectChanges();

        expect(fixture.nativeElement.innerText).toContain('Elphaba Thropp');
        expect(fixture.nativeElement.innerText).toContain('Fiyero Tigelaar');
        expect(fixture.nativeElement.innerText).toContain('Glinda Upland');
        expect(fixture.nativeElement.innerText).not.toContain('…');

        component.characterLimit = null;
        fixture.detectChanges();

        expect(fixture.nativeElement.innerText).toContain('Elphaba Thropp');
        expect(fixture.nativeElement.innerText).toContain('Fiyero Tigelaar');
        expect(fixture.nativeElement.innerText).toContain('Glinda Upland');
        expect(fixture.nativeElement.innerText).not.toContain('…');
    });
    it('does not show expand button if entry limit is the same as the number of items', () => {
        component.entryLimit = 1;
        component.entries = [
            {text: '317 pages'},
        ];
        fixture.detectChanges();

        expect(fixture.nativeElement.querySelector('button')).toBeFalsy();
    });
    it('displays links when routerLink and queryParams are set and displayLink is true', () => {
        component.entries = [
            {text: 'Garbonzo', routerLink: '/eg2/staff/garbonzo', queryParams: {}, displayLink: true},
        ];
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('a')).toBeTruthy();
    });
    it('does not display links when displayLink is false', () => {
        component.entries = [
            {text: 'Garbonzo', routerLink: '/eg2/staff/garbonzo', displayLink: false},
        ];
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('a')).toBeFalsy();
    });
});
