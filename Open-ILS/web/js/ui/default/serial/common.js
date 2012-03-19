function attempt_reload_opac() {
    try {
        xulG.reload_opac();
    } catch (E) {
        (dump || console.log)(E);
    }
}
