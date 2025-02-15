import { NgTemplateOutlet } from '@angular/common';
import { Component, Input, TemplateRef } from '@angular/core';

@Component({
    standalone: true,
    imports: [NgTemplateOutlet],
    template: '<div class="row"><div class="col-sm-4"><ng-container *ngTemplateOutlet="label"></ng-container>:</div>' +
        '<div class="col-sm-8"><ng-container *ngTemplateOutlet="value"></ng-container></div></div>'
})
export class StaffRecordSummaryLayoutComponent {
    @Input() label: TemplateRef<any>;
    @Input() value: TemplateRef<any>;
}
