/*j
 * <eg-string #helloStr text="Hello, {{name}}" i18n-text></eg-string>
 *
 * import {StringComponent} from '@eg/share/string.component';
 * @ViewChild('helloStr') private helloStr: StringComponent;
 * ...
 * this.helloStr.currrent().then(s => console.log(s));
 *
 */
import {Component, Input, OnInit, ElementRef, TemplateRef} from '@angular/core';
import {StringService} from '@eg/share/string/string.service';

@Component({
  selector: 'eg-string',
  template: `
    <span style='display:none'>
      <ng-container *ngIf="template">
        <ng-container *ngTemplateOutlet="template; context:ctx"></ng-container>
      </ng-container>
      <ng-container *ngIf="!template">
        <span>{{text}}</span>
      </ng-container>
    </span>
  `
})

export class StringComponent implements OnInit {

    // Storage key for future reference by the string service
    @Input() key: string;

    // Interpolation context
    @Input() ctx: any;

    // String template to interpolate
    @Input() template: TemplateRef<any>;

    // Static text -- no interpolation performed.
    // This supersedes 'template'
    @Input() text: string;

    constructor(private elm: ElementRef, private strings: StringService) {
        this.elm = elm;
        this.strings = strings;
    }

    ngOnInit() {
        // No key means it's an unregistered (likely static) string
        // that does not need interpolation.
        if (this.key) {
            this.strings.register({
                key: this.key,
                resolver: (ctx: any) => {
                    if (this.text) {
                        // When passed text that does not require any
                        // interpolation, just return it as-is.
                        return Promise.resolve(this.text);
                    } else {
                        // Interpolate
                        return this.current(ctx);
                    }
                }
            });
        }
    }

    // Apply the new context if provided, give our container a
    // chance to update, then resolve with the current string.
    // NOTE: talking to the native DOM element is not so great, but
    // hopefully we can retire the String* code entirely once
    // in-code translations are supported (Ang6?)
    async current(ctx?: any): Promise<string> {
        if (ctx) { this.ctx = ctx; }
        return new Promise<string>(resolve =>
            setTimeout(() => resolve(this.elm.nativeElement.textContent))
        );
    }
}

