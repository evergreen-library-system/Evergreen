import { Directive, ElementRef, Input, Renderer2 } from '@angular/core';

export type ButtonStyle = {
    primary?: boolean;
    secondary?: boolean;
    success?: boolean;
    danger?: boolean;
    warning?: boolean;
    info?: boolean;
    light?: boolean;
    dark?: boolean;
    link?: boolean;
    outline?: boolean;
};

@Directive({
    selector: '[egButtonStyle]'
})
export class ButtonStyleDirective {
    @Input('egButtonStyle') set buttonStyle(value: ButtonStyle) {
        this.updateClasses(value);
    }

    private readonly buttonTypes = [
        'primary', 'secondary', 'success', 'danger',
        'warning', 'info', 'light', 'dark', 'link',
        'normal', 'destroy'
    ];

    constructor(private el: ElementRef, private renderer: Renderer2) {}

    private updateClasses(style: ButtonStyle) {
        // Always ensure the base 'btn' class is present
        this.renderer.addClass(this.el.nativeElement, 'btn');

        // Remove any existing button classes
        this.buttonTypes.forEach(type => {
            this.renderer.removeClass(this.el.nativeElement, `btn-${type}`);
            this.renderer.removeClass(this.el.nativeElement, `btn-outline-${type}`);
        });

        // Apply the appropriate class based on the input
        if (typeof style === 'object') {
            for (const [key, value] of Object.entries(style)) {
                if (value && this.buttonTypes.includes(key)) {
                    const prefix = style.outline ? 'btn-outline-' : 'btn-';
                    this.renderer.addClass(this.el.nativeElement, `${prefix}${key}`);
                    break; // Only apply the first true value
                }
            }
        } else {
            // sane? somewhere along the line we made some buttons very plain and not obviously buttons
            this.renderer.addClass(this.el.nativeElement, 'btn-normal');
        }
    }
}
