import {NgModule} from '@angular/core';
import {EgCoreModule} from '@eg/core/core.module';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';


@NgModule({
    imports: [
        EgCoreModule,
        StringComponent
    ],
    exports: [
        StringComponent
    ]
})

export class StringModule { }

