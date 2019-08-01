import {Component, OnInit, ViewChild, TemplateRef} from '@angular/core';

@Component({
    templateUrl: './address-alert.component.html'
})

export class AddressAlertComponent {

    @ViewChild('helpTemplate') helpTemplate: TemplateRef<any>;

    constructor() {}
}

