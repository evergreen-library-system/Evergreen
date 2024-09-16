import {Component, TemplateRef, OnInit, Input, ViewEncapsulation} from '@angular/core';

@Component({
    selector: 'eg-staff-banner',
    template: `
    <eg-title i18n-prefix [prefix]="bannerText"></eg-title>

    <div class="staff-banner" [ngClass]="bannerStyle">
      <h1 id="staff-banner" tabindex="0" *ngIf="bannerText || bannerIcon">
        <i class="material-icons align-middle text-left" aria-hidden="true" *ngIf="bannerIcon">{{bannerIcon}}</i>
        <span i18n>{{bannerText}}</span>
      </h1>
      <ng-container *ngIf="bannerTemplateRef">
        <ng-container *ngTemplateOutlet="bannerTemplateRef"></ng-container>
      </ng-container>
    </div>
    `,
    styleUrls: ['staff-banner.component.css'],
    encapsulation: ViewEncapsulation.None
})

export class StaffBannerComponent {
    @Input() public bannerText: string;
    @Input() public bannerIcon: string;
    @Input() public bannerStyle: string;
    @Input() public bannerTemplateRef: TemplateRef<any>; // replaces bannerText in the heading, but not the title
}


