export class EresourceClickTrack {
    setup(selector) {
        if(window.navigator.sendBeacon) {
            document.querySelectorAll(selector).forEach(link => {
                link.addEventListener('click', () => {
                    const data = new FormData();
                    data.append('record_id', link.getAttribute('data-record-id'));
                    data.append('url', link.getAttribute('href'));
                    window.navigator.sendBeacon('/opac/extras/eresource_link_click_track', data);
                });
            });
        }
    }
}
