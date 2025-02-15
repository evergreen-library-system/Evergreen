import { NgTemplateOutlet } from '@angular/common';
import { Component, Input, TemplateRef } from '@angular/core';


@Component({
    standalone: true,
    imports: [NgTemplateOutlet],
    template: '<div class="pb-1"><ng-content *ngTemplateOutlet="label"/>' +
        '<ng-container i18n="catalog-label-metadata-delimiter">: </ng-container>' +
        '<ng-content *ngTemplateOutlet="value"/></div>'
})
export class ResultsMetadataLayoutComponent {
    @Input() label: TemplateRef<any>;
    @Input() value: TemplateRef<any>;
}

