import { Component, computed, ElementRef, input, signal, viewChild } from '@angular/core';
import { Params, RouterModule } from '@angular/router';
import { SnippetPipe } from '../pipes/snippet_pipe';

const HALF_SECOND = 500;

@Component({
    selector: 'eg-show-more',
    standalone: true,
    imports: [RouterModule, SnippetPipe],
    templateUrl: './show-more.component.html',
    styles: ':host { display: flex; }'
})
export class ShowMoreComponent {
    protected text = input('');
    protected characterLimit = input<number>();
    // if href provided, use it to create a link when displayLink is true
    protected displayLink = input(true);
    protected routerLink = input<string | any[]>();
    protected queryParams = input<Params>();

    protected collapsed = signal(true);

    private collapsedText = viewChild<ElementRef>('collapsedText');
    private expandedText = viewChild<ElementRef>('expandedText');

    protected shouldTruncate = computed(() => {
        if (!this.characterLimit()) {
            return false;
        }
        if (this.text().length < this.characterLimit()) {
            return false;
        }
        return true;
    });

    protected expand(): void {
        this.collapsed.set(false);
        this.setFocus();
    }

    protected collapse(): void {
        this.collapsed.set(true);
    }

    protected setFocus(): void {
        // A brief pause for the screen reader's virtual buffer
        // to read the new DOM element into memory, then set focus
        // to inform the screen reader user of the newly expanded
        // content.
        setTimeout(() => {
            const elementToFocus = (this.collapsedText() || this.expandedText())?.nativeElement;
            elementToFocus?.focus({ preventScroll: true });
        }, HALF_SECOND);
    }
}
