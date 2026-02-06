import { enableProdMode, importProvidersFrom } from '@angular/core';
import { platformBrowserDynamic } from '@angular/platform-browser-dynamic';


import { environment } from './environments/environment';
import { EgCommonModule } from './app/common.module';
import { BaseRoutingModule } from './app/routing.module';
import { BrowserModule, bootstrapApplication } from '@angular/platform-browser';
import { NgbModule } from '@ng-bootstrap/ng-bootstrap';
import { CookieModule } from 'ngx-cookie';
import { BaseComponent } from './app/app.component';

if (environment.production) {
    enableProdMode();
}

bootstrapApplication(BaseComponent, {
    providers: [importProvidersFrom(EgCommonModule.forRoot(), BaseRoutingModule, BrowserModule, NgbModule, CookieModule.forRoot())]
})
    .catch(err => console.log(err));
