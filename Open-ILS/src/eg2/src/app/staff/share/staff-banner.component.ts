import {Component, OnInit, Input} from '@angular/core';

@Component({
  selector: 'eg-staff-banner',
  template: `
    <div class="lead alert alert-primary text-center pt-1 pb-1">
      <eg-title i18n-prefix [prefix]="bannerText"></eg-title>
       <span>{{bannerText}}</span>
    </div>
    `
})

export class StaffBannerComponent {
    @Input() public bannerText: string;
}


