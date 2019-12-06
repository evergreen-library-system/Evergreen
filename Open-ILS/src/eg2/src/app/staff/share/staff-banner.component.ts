import {Component, OnInit, Input} from '@angular/core';

@Component({
  selector: 'eg-staff-banner',
  template: `
    <div class="lead alert alert-primary text-center pt-1 pb-1"
      [ngClass]="bannerStyle ? bannerStyle : 'alert-primary'">
      <eg-title i18n-prefix [prefix]="bannerText"></eg-title>
      <i class="material-icons align-middle text-left" *ngIf="bannerIcon">{{bannerIcon}}</i>
       <span class="align-middle">{{bannerText}}</span>
    </div>
    `
})

export class StaffBannerComponent {
    @Input() public bannerText: string;
    @Input() public bannerIcon: string;
    @Input() public bannerStyle: string;
}


