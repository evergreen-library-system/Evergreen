import { CommonModule } from '@angular/common';
import {Component, TemplateRef, Input, ViewEncapsulation} from '@angular/core';
import { TitleComponent } from '@eg/share/title/title.component';

@Component({
    selector: 'eg-staff-banner',
    template: `
    <eg-title i18n-prefix [prefix]="bannerText"></eg-title>

    <div class="staff-banner" [ngClass]="bannerStyle">
      @if (bannerText || bannerIcon) {
        <h1 id="staff-banner" tabindex="0">
          @if (bannerIcon) {
            <i class="material-icons align-middle text-start" aria-hidden="true">{{bannerIcon}}</i>
          }
          <span i18n>{{bannerText}}</span>
        </h1>
      }
      @if (bannerTemplateRef) {
        <ng-container *ngTemplateOutlet="bannerTemplateRef"></ng-container>
      }
    </div>
    `,
    styleUrls: ['staff-banner.component.css'],
    encapsulation: ViewEncapsulation.None,
    imports: [
        CommonModule,
        TitleComponent
    ]
})

export class StaffBannerComponent {
    @Input() public bannerText: string;
    @Input() public bannerIcon: string;
    @Input() public bannerStyle: string;
    @Input() public bannerTemplateRef: TemplateRef<any>; // replaces bannerText in the heading, but not the title
}


