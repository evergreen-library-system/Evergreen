import { ComponentFixture, TestBed, fakeAsync, flush, tick } from '@angular/core/testing';
import { TreeComboboxComponent } from './tree-combobox.component';
import { Tree, TreeNode } from '../tree/tree';

// non-collapsing space
const PAD_SPACE = ' '; // U+2007

function waitForDebounce() {
    tick(200);
}

describe('TreeComboboxComponent', () => {
    let component: TreeComboboxComponent;
    let fixture: ComponentFixture<TreeComboboxComponent>;
    let rootNode: TreeNode;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ TreeComboboxComponent ]
        })
            .compileComponents();

        fixture = TestBed.createComponent(TreeComboboxComponent);
        component = fixture.componentInstance;
        rootNode = new TreeNode({
            id: 1,
            label: 'Metals',
            children: [
                new TreeNode({id: 2, label: 'Mercury'}),
                new TreeNode({id: 3, label: 'Silver'})
            ]
        });
        component.tree = new Tree(rootNode);
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('uses spaces to indent child entries', fakeAsync(() => {
        fixture.nativeElement.querySelector('input').focus();

        flush();
        const entries = fixture.nativeElement.querySelectorAll('button.dropdown-item');
        expect(entries[0].textContent).toEqual('Metals');
        expect(entries[1].textContent).toEqual(PAD_SPACE + 'Mercury');
        expect(entries[2].textContent).toEqual(PAD_SPACE + 'Silver');
    }));

    it('limits entries to matches', fakeAsync(() => {
        const input = fixture.nativeElement.querySelector('input');
        input.focus();

        input.value = 'm';
        input.dispatchEvent(new Event('input', { 'bubbles': true }));
        waitForDebounce();
        flush();

        const entries = fixture.nativeElement.querySelectorAll('button.dropdown-item');
        expect(entries.length).toEqual(2);
        expect(entries[0].textContent).toEqual('Metals');
        expect(entries[1].textContent).toEqual(PAD_SPACE + 'Mercury');
    }));

    it('emits a nodeSelected event with the treenode', () => {
        let emitted: TreeNode;
        component.nodeSelected$.subscribe((event: TreeNode) => {
            emitted = event;
        });

        fixture.nativeElement.querySelector('input').focus();
        fixture.debugElement.query(
            debugEl => debugEl.nativeElement.textContent === 'Metals'
        ).nativeElement.click();

        expect(emitted).toEqual(rootNode);
    });

    it('displays the selected node in the <input>', () => {
        const input = fixture.nativeElement.querySelector('input');

        input.focus();
        fixture.debugElement.query(
            debugEl => debugEl.nativeElement.textContent === 'Metals'
        ).nativeElement.click();

        expect(input.value).toEqual('Metals');
    });

    it('can display a placeholder', () => {
        component.placeholder = 'Here is my placeholder';
        fixture.detectChanges();

        const input = fixture.nativeElement.querySelector('input');
        expect(input.getAttribute('placeholder')).toEqual('Here is my placeholder');
    });

    it('does not include a placeholder if none is specified', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.hasAttribute('placeholder')).toEqual(false);
    });

    it('can provide an aria-label', () => {
        component.ariaLabel = 'Here is my aria label';
        fixture.detectChanges();

        const input = fixture.nativeElement.querySelector('input');
        expect(input.getAttribute('aria-label')).toEqual('Here is my aria label');
    });

    it('does not include an aria-label if none is specified', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.hasAttribute('aria-label')).toEqual(false);
    });

    it('can provide a domId', () => {
        component.domId = 'my-library';
        fixture.detectChanges();

        const input = fixture.nativeElement.querySelector('input');
        expect(input.getAttribute('id')).toEqual('my-library');
    });

    it('does not include an id if none is specified', () => {
        const input = fixture.nativeElement.querySelector('input');
        expect(input.hasAttribute('id')).toEqual(false);
    });

    it('can display a default value in the input', fakeAsync(() => {
        component.defaultNode = new TreeNode({id: 13, label: 'Molybdenum'});
        fixture.detectChanges();
        waitForDebounce();

        const input = fixture.nativeElement.querySelector('input');
        expect(input.value).toEqual('Molybdenum');
    }));
});
