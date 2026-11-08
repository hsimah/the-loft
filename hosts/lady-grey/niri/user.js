// Lady Grey kiosk profiles (dashboard and photo frame). Firefox re-reads
// user.js on every start. niri's output scale handles HiDPI; touch works
// natively on Wayland.
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.translations.automaticallyPopup", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
