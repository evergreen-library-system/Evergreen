import { AfterViewInit, Directive, ElementRef, inject } from '@angular/core';

@Directive({
    selector: '[egFocusOnViewInit]',
    standalone: true
})
export class FocusOnViewInitDirective implements AfterViewInit {
    private readonly host = inject(ElementRef);

    ngAfterViewInit() {
        this.host.nativeElement.focus();
    }
}
