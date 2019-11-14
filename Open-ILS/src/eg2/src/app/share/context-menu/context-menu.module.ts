import {NgModule} from '@angular/core';
import {CommonModule} from '@angular/common';
import {NgbModule} from '@ng-bootstrap/ng-bootstrap';
import {ContextMenuService} from './context-menu.service';
import {ContextMenuDirective} from './context-menu.directive';
import {ContextMenuContainerComponent} from './context-menu-container.component';

@NgModule({
  declarations: [
    ContextMenuDirective,
    ContextMenuContainerComponent
  ],
  imports: [
    CommonModule,
    NgbModule
  ],
  exports: [
    ContextMenuDirective,
    ContextMenuContainerComponent
  ]
})

export class ContextMenuModule { }

