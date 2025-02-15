import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ShowMoreComponent } from './show-more.component';
import { provideRouter } from '@angular/router';

describe('ShowMoreComponent', () => {
    let component: ShowMoreComponent;
    let fixture: ComponentFixture<ShowMoreComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ ShowMoreComponent ],
            providers: [provideRouter([])]
        })
            .compileComponents();

        fixture = TestBed.createComponent(ShowMoreComponent);
        component = fixture.componentInstance;
        fixture.componentRef.setInput(
            'text',
            'Call me Ishmael. Some years ago—never mind how long precisely—having ' +
            'little or no money in my purse, and nothing particular to interest me on shore, I thought' +
            'I would sail about a little and see the watery part of the world. It is a way I have of' +
            'driving off the spleen and regulating the circulation.'
        );
        fixture.componentRef.setInput('characterLimit', 50);
        fixture.detectChanges();
    });

    it('shows the first part of the text', () => {
        expect(fixture.nativeElement.innerText).toContain('Call me Ishmael. Some years ago—never mind how…');
        expect(fixture.nativeElement.innerText).not.toContain('driving off the spleen');
    });
    it('does not truncate strings that are shorter than the limit', () => {
        fixture.componentRef.setInput('text', 'Call me Ishmael.');
        fixture.detectChanges();
        expect(fixture.nativeElement.innerText).toContain('Call me Ishmael.');
        expect(fixture.nativeElement.innerText).not.toContain('…');
    });
    it('does not truncate strings that are a single long word', () => {
        fixture.componentRef.setInput('text', 'Supercalifragilisticexpialidocious');
        fixture.componentRef.setInput('characterLimit', 15);
        fixture.detectChanges();
        expect(fixture.nativeElement.innerText).toContain('Supercalifragilisticexpialidocious');
    });
    it('includes a more button', () => {
        expect(fixture.nativeElement.querySelector('button').innerText).toEqual('Read more');
        expect(fixture.nativeElement.querySelector('button').getAttribute('aria-expanded')).toEqual('false');
    });
    it('opens when the more button is pressed', () => {
        fixture.nativeElement.querySelector('button').click();
        fixture.detectChanges();

        expect(fixture.nativeElement.querySelector('button').innerText).toEqual('Read less');
        expect(fixture.nativeElement.querySelector('button').getAttribute('aria-expanded')).toEqual('true');
        expect(fixture.nativeElement.innerText).toContain('driving off the spleen');
    });
    it('sets focus on the content half a second after click', (done) => {
        jasmine.clock().install();
        fixture.nativeElement.querySelector('button').click();
        fixture.detectChanges();
        jasmine.clock().tick(500);

        expect(document.activeElement.tagName).toEqual('SPAN');
        expect(document.activeElement.textContent).toContain('driving off the spleen');
        jasmine.clock().uninstall();
        done();
    });
    describe('when characterLimit is null', () => {
        beforeEach(() => {
            fixture.componentRef.setInput('characterLimit', null);
            fixture.detectChanges();
        });
        it('does not truncate', () => {
            expect(fixture.nativeElement.innerText).toContain('Call me Ishmael.');
            expect(fixture.nativeElement.innerText).toContain('driving off the spleen');
            expect(fixture.nativeElement.innerText).not.toContain('…');
            expect(fixture.nativeElement.querySelector('button')).toBeFalsy();
        });
    });
    describe('when routerLink and queryParams are provided', () => {
        beforeEach(() => {
            fixture.componentRef.setInput('routerLink', '/eg2/staff/catalog/search');
            fixture.componentRef.setInput('queryParams', {query: 'hello'});
        });
        it('displays a link if displayLink is true', () => {
            fixture.componentRef.setInput('displayLink', true);
            fixture.detectChanges();
            expect(fixture.nativeElement.querySelector('a')).toBeTruthy();
        });
        it('does not display the text multiple times if displayLink is true', () => {
            fixture.componentRef.setInput('displayLink', true);
            fixture.detectChanges();

            const textContentCount = fixture.nativeElement.textContent.match(/Call me Ishmael/g).length;
            expect(textContentCount).toEqual(1);
        });
        it('does not display a link if displayLink is false', () => {
            fixture.componentRef.setInput('displayLink', false);
            fixture.detectChanges();
            expect(fixture.nativeElement.querySelector('a')).toBeFalsy();
        });
    });
});
