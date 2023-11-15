interface Scripts {
  name: string;
  src?: string;
  reloadable: boolean;
  setting?: string;
}
export const ScriptStore: Scripts[] = [
    { name: 'novelist', src: 'https://imageserver.ebscohost.com/novelistselect/ns2init.js',
        setting: 'staff.added_content.novelistselect.url', reloadable: false },
    { name: 'novelist-loading', src: '/eg/staff/ngNSelect_js', reloadable: true}
];
