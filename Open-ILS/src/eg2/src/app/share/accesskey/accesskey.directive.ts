/**
 * Assign access keys to <a> tags.
 *
 * Access key action is peformed via .click(). hrefs, routerLinks,
 * and (click) actions are all supported.
 *
 *   <a
 *     routerLink="/staff/splash"
 *     egAccessKey
 *     keySpec="alt+h" i18n-keySpec
 *     keyDesc="My Description" 18n-keyDesc
 *   >
 */
import {Directive, ElementRef, Input, OnInit} from '@angular/core';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';

@Directive({
  selector: '[egAccessKey]'
})
export class AccessKeyDirective implements OnInit {

    // Space-separated list of key combinations
    // E.g. "ctrl+h", "alt+h ctrl+y"
    @Input() keySpec: string;

    // Description to display in the accesskey info dialog
    @Input() keyDesc: string;

    // Context info to display in the accesskey info dialog
    // E.g. "navbar"
    @Input() keyCtx: string;

    constructor(
        private elm: ElementRef,
        private keyService: AccessKeyService
    ) { }

    ngOnInit() {

        if (!this.keySpec) {
            console.warn('AccessKey no keySpec provided');
            return;
        }

        this.keySpec.split(/ /).forEach(keySpec => {
            this.keyService.assign({
                key: keySpec,
                desc: this.keyDesc,
                ctx: this.keyCtx,
                action: () => this.elm.nativeElement.click()
            });
        });
    }
}


