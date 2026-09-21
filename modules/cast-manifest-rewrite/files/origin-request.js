"use strict";

const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");

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

// Same approach as ufb's img-resizer origin-response Lambda: read a stream
// into a Buffer via plain event listeners, rather than relying on the
// AWS SDK response body's transformToString() convenience method, which
// depends on a @smithy/util-stream mixin version this Lambda@Edge runtime
// may or may not carry.
function streamToBuffer(stream) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    stream.on("data", (chunk) => chunks.push(chunk));
    stream.on("error", reject);
    stream.on("end", () => resolve(Buffer.concat(chunks)));
  });
}

function createHandler(s3Client) {
  return async function handler(event) {
    const request = event.Records[0].cf.request;

    // Browser playback authorizes every /audio/* request with a signed
    // cookie and never attaches a query string to the request itself —
    // leave those untouched. Only a Cast session's signed-URL fetch (see
    // ufb backend's upfrontbeats/utils/cloudfront_util.py) carries one.
    if (
      request.method !== "GET" ||
      !request.uri.endsWith(".m3u8") ||
      !request.querystring
    ) {
      return request;
    }

    // Lambda@Edge functions on an origin-response/viewer-response event
    // cannot read the body of the response CloudFront already fetched —
    // include_body only exists for request bodies on
    // viewer-request/origin-request, and response bodies are never
    // exposed to a response-event Lambda at all. The only way to
    // read-and-rewrite the manifest is to fetch it ourselves here, on
    // origin-request, and short-circuit the real origin fetch entirely by
    // returning a complete response object — Lambda@Edge lets an
    // origin-request function do that instead of returning a (possibly
    // modified) request.
    const bucketName = request.origin?.s3?.domainName?.replace(
      ".s3.amazonaws.com",
      "",
    );
    const bucketPath = request.origin?.s3?.path?.replace(/^\//, "");

    if (!bucketName) return request;

    const key = bucketPath ? `${bucketPath}${request.uri}` : request.uri.replace(/^\//, "");

    try {
      const object = await s3Client.send(
        new GetObjectCommand({ Bucket: bucketName, Key: key }),
      );
      const manifest = (await streamToBuffer(object.Body)).toString("utf-8");

      return {
        status: "200",
        statusDescription: "OK",
        headers: {
          "content-type": [
            { key: "Content-Type", value: "application/vnd.apple.mpegurl" },
          ],
        },
        body: propagateQueryStringToManifest(manifest, request.querystring),
      };
    } catch {
      // Falls back to the real origin fetch on any failure (missing
      // object, S3 error, etc.). The manifest itself is still separately
      // authorized by CloudFront's own signed-URL check regardless — it
      // just won't have the propagated query string on its segment URIs,
      // so those segment requests 403 rather than the whole request
      // failing outright.
      return request;
    }
  };
}

const s3 = new S3Client({});

exports.handler = createHandler(s3);
exports.createHandler = createHandler;
exports.propagateQueryStringToManifest = propagateQueryStringToManifest;
