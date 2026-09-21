"use strict";

// A signed cookie (browser playback) auto-attaches to every request the
// player makes, so one cookie authorizes the manifest and every segment
// fetch after it. A signed URL only authorizes the one request it's
// attached to — fine for a Chromecast receiver's initial manifest fetch,
// but every segment/sub-playlist URI the manifest itself references then
// gets fetched as a plain, unsigned request. This propagates the same
// query string onto those URIs, so CloudFront's existing wildcard-resource
// policy (already covering /audio/{id}/cmaf/*) authorizes them too.
const URI_ATTRIBUTE_REGEX = /URI="([^"]+)"/;

function appendQueryString(uri, querystring) {
  const separator = uri.includes("?") ? "&" : "?";
  return `${uri}${separator}${querystring}`;
}

function propagateQueryStringToManifest(manifest, querystring) {
  if (!querystring) return manifest;

  return manifest
    .split("\n")
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed) return line;

      // Tag lines (e.g. #EXT-X-MAP, #EXT-X-MEDIA) carry their URI as a
      // quoted attribute rather than the whole line being the URI.
      if (trimmed.startsWith("#")) {
        const match = trimmed.match(URI_ATTRIBUTE_REGEX);
        if (!match) return line;
        const rewritten = appendQueryString(match[1], querystring);
        return line.replace(URI_ATTRIBUTE_REGEX, `URI="${rewritten}"`);
      }

      // Any other non-empty line is itself a URI: a segment, an init
      // segment, or a nested (variant) playlist reference.
      return appendQueryString(trimmed, querystring);
    })
    .join("\n");
}

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const response = event.Records[0].cf.response;

  // Browser playback authorizes every /audio/* request with a signed
  // cookie and never attaches a query string to the request itself — leave
  // those responses untouched. Only a Cast session's signed-URL fetch
  // (ufb backend's upfrontbeats/utils/cloudfront_util.py) carries one.
  if (!request.uri.endsWith(".m3u8") || !request.querystring) {
    return response;
  }

  if (!response.body) {
    return response;
  }

  const body =
    response.bodyEncoding === "base64"
      ? Buffer.from(response.body, "base64").toString("utf-8")
      : response.body;

  response.body = propagateQueryStringToManifest(body, request.querystring);
  response.bodyEncoding = "text";

  return response;
};

exports.propagateQueryStringToManifest = propagateQueryStringToManifest;
