function sendTestEmail(user_id, authtoken) {
    sendTestNotification(user_id, 'au.email.test', authtoken);
}

function sendTestSMS(user_id, authtoken) {
    sendTestNotification(user_id, 'au.sms_text.test', authtoken);
}

function sendTestNotification(user_id, hook, authtoken) {

    var args = {
        target: user_id,
        hook: hook
    };

    new OpenSRF.ClientSession('open-ils.actor').request({
        method: 'open-ils.actor.event.test_notification',
        params: [authtoken, args],
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                var banner = document.getElementById('test_notification_banner');
                banner.style.display = 'block';
            }
        }
    }).send();
}