/**
 * BaseModule is the shared starting point for all apps.  It provides
 * the root route and a simple welcome page for users that end up here
 * accidentally.
 */
import {BrowserModule} from '@angular/platform-browser';
import {NgModule} from '@angular/core';
import {NgbModule} from '@ng-bootstrap/ng-bootstrap'; // ng-bootstrap
import {CookieModule} from 'ngx-cookie'; // import CookieMonster

import {EgCommonModule} from './common.module';
import {BaseComponent} from './app.component';
import {BaseRoutingModule} from './routing.module';
import {WelcomeComponent} from './welcome.component';

@NgModule({
  declarations: [
    BaseComponent,
    WelcomeComponent
  ],
  imports: [
    EgCommonModule.forRoot(),
    BaseRoutingModule,
    BrowserModule,
    NgbModule,
    CookieModule.forRoot()
  ],
  exports: [],
  bootstrap: [BaseComponent]
})

export class BaseModule {}

