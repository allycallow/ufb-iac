// Plain JS, not TypeScript: this file isn't built by anything — it's
// uploaded to S3 as-is by this module (see ../main.tf) and runs standalone
// in the Chromecast device's own browser environment via index.html's
// <script> tag.
(function () {
  var context = cast.framework.CastReceiverContext.getInstance();
  var playerManager = context.getPlayerManager();

  // The sender (buildCastMediaInfo() in ufb-frontend's
  // src/components/Player/index.tsx) attaches the license URL(s) it already
  // configures for local Shaka playback as mediaInfo.customData.drm, keyed
  // per-load rather than hardcoded here, so this receiver doesn't need its
  // own copy of EZDRM's URL/account details to stay in sync with the sender.
  playerManager.setMediaPlaybackInfoHandler(function (
    loadRequest,
    playbackConfig,
  ) {
    var drm =
      loadRequest.media &&
      loadRequest.media.customData &&
      loadRequest.media.customData.drm;
    if (!drm) return playbackConfig;

    // Real Chromecast hardware only ever implements Widevine — playready is
    // included for parity with the sender's local (desktop Edge) DRM config,
    // in case this receiver code is ever reused outside actual Cast devices.
    if (drm.widevineLicenseUrl) {
      playbackConfig.licenseUrl = drm.widevineLicenseUrl;
      playbackConfig.protectionSystem = cast.framework.ContentProtection.WIDEVINE;
    } else if (drm.playreadyLicenseUrl) {
      playbackConfig.licenseUrl = drm.playreadyLicenseUrl;
      playbackConfig.protectionSystem = cast.framework.ContentProtection.PLAYREADY;
    }

    return playbackConfig;
  });

  var options = new cast.framework.CastReceiverOptions();
  options.maxInactivity = 3600;

  context.start(options);
})();
