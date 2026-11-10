export type SipMediaType = {
    value: string,
    mediaType: string
};

export const SIP_MEDIA_TYPES = [
    {value: '000', mediaType: $localize`:SIP media type:other`},
    {value: '001', mediaType: $localize`:SIP media type:book`},
    {value: '002', mediaType: $localize`:SIP media type:magazine`},
    {value: '003', mediaType: $localize`:SIP media type:bound journal`},
    {value: '004', mediaType: $localize`:SIP media type:audio tape`},
    {value: '005', mediaType: $localize`:SIP media type:video tape`},
    {value: '006', mediaType: $localize`:SIP media type:CD/CDROM`},
    {value: '007', mediaType: $localize`:SIP media type:diskette`},
    {value: '008', mediaType: $localize`:SIP media type:book with diskette`},
    {value: '009', mediaType: $localize`:SIP media type:book with CD`},
    {value: '010', mediaType: $localize`:SIP media type:book with audio tape`},
];

export function sipMediaTypeLabel(value: string): string {
    return SIP_MEDIA_TYPES.find(type => type.value === value)?.mediaType;
}

export const DEFAULT_SIP_MEDIA_TYPE = '001'; // book
