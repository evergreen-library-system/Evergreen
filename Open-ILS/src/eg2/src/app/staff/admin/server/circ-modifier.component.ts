import { Component, inject, OnInit } from '@angular/core';
import { AdminCommonModule } from '../common.module';
import { SelectComponent, SelectOption } from '@eg/share/select/select.component';
import { DEFAULT_SIP_MEDIA_TYPE, SIP_MEDIA_TYPES, sipMediaTypeLabel } from '@eg/staff/share/sip';
import { upcaseFirst } from '@eg/share/util/letter-case';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { GridDataSource } from '@eg/share/grid/grid';
import { PcrudService } from '@eg/core/pcrud.service';
import { basicSearchBuilder, basicSearchFn, basicSearchOptsBuilder, buildPcrudGridDataSource } from '@eg/share/grid/build-grid-data-source';
import { map } from 'rxjs';

@Component({
    selector: 'eg-circ-modifier',
    standalone: true,
    imports: [AdminCommonModule, SelectComponent],
    templateUrl: './circ-modifier.component.html'
})
export class CircModifierComponent implements OnInit {
    protected dataSource: GridDataSource;
    protected sipModifiers: SelectOption[] = SIP_MEDIA_TYPES.map(type => {return {value: type.value, label: upcaseFirst(type.mediaType)};});
    protected defaultNewRecord: IdlObject;
    protected CIRC_MODIFIER_IDL_CLASS = 'ccm';

    private idl = inject(IdlService);
    private pcrud = inject(PcrudService);

    ngOnInit(): void {
        this.defaultNewRecord = this.idl.create(this.CIRC_MODIFIER_IDL_CLASS);
        this.defaultNewRecord.sip2_media_type(DEFAULT_SIP_MEDIA_TYPE);
        this.defaultNewRecord.magnetic_media(true);

        this.dataSource = buildPcrudGridDataSource(
            this.CIRC_MODIFIER_IDL_CLASS,
            this.pcrud,
            basicSearchBuilder,
            basicSearchOptsBuilder,
            (fmClass, pcrud, search, searchOps) =>
                basicSearchFn(fmClass, pcrud, search, searchOps)
                    .pipe(map(circModifier => this.humanReadableCircModifier(circModifier))),
        );
    }

    // relabel the sip2_media_type field (which is stored
    // in the database as a code like 003) into a more
    // user-friendly label
    private humanReadableCircModifier(circModifier: IdlObject): IdlObject {
        circModifier.sip2_media_type(sipMediaTypeLabel(circModifier.sip2_media_type()));
        return circModifier;
    }
}
