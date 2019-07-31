/**
 * Core objects.
 * Note that core services are generally defined with
 * @Injectable({providedIn: 'root'}) so they are globally available
 * and do not require entry in our 'providers' array.
 */
import {NgModule} from '@angular/core';
import {CommonModule, DatePipe, CurrencyPipe} from '@angular/common';
import {FormatService, FormatValuePipe} from './format.service';

@NgModule({
  declarations: [
    FormatValuePipe
  ],
  imports: [
    CommonModule
  ],
  exports: [
    CommonModule,
    FormatValuePipe
  ],
  providers: [
    DatePipe,
    CurrencyPipe
  ]
})

export class EgCoreModule {}

