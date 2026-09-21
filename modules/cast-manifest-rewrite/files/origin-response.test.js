"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { handler, propagateQueryStringToManifest } = require("./origin-response");

const QS = "Policy=abc&Signature=def&Key-Pair-Id=ghi";

test("propagateQueryStringToManifest appends the query string to plain segment lines", () => {
  const manifest = ["#EXTM3U", "#EXTINF:6.0,", "segment0.m4s"].join("\n");

  const result = propagateQueryStringToManifest(manifest, QS);

  assert.match(result, new RegExp(`segment0\\.m4s\\?${QS}$`, "m"));
});

test("propagateQueryStringToManifest rewrites the URI attribute on tag lines", () => {
  const manifest = ['#EXT-X-MAP:URI="init.mp4"', "segment0.m4s"].join("\n");

  const result = propagateQueryStringToManifest(manifest, QS);

  assert.ok(result.includes(`URI="init.mp4?${QS}"`));
});

test("propagateQueryStringToManifest leaves plain tag lines with no URI untouched", () => {
  const manifest = ["#EXTM3U", "#EXT-X-VERSION:7"].join("\n");

  const result = propagateQueryStringToManifest(manifest, QS);

  assert.equal(result, manifest);
});

test("propagateQueryStringToManifest is a no-op with an empty query string", () => {
  const manifest = ["#EXTM3U", "segment0.m4s"].join("\n");

  assert.equal(propagateQueryStringToManifest(manifest, ""), manifest);
});

test("handler passes non-.m3u8 responses through untouched", async () => {
  const response = { status: "200", headers: {} };
  const event = {
    Records: [
      {
        cf: {
          request: { uri: "/audio/abc/cmaf/segment0.m4s", querystring: QS },
          response,
        },
      },
    ],
  };

  const result = await handler(event);

  assert.equal(result, response);
});

test("handler passes .m3u8 responses through untouched when there's no query string (cookie-authorized browser playback)", async () => {
  const response = { status: "200", headers: {}, body: "#EXTM3U\nsegment0.m4s" };
  const event = {
    Records: [
      {
        cf: {
          request: { uri: "/audio/abc/cmaf/playlist.m3u8", querystring: "" },
          response,
        },
      },
    ],
  };

  const result = await handler(event);

  assert.equal(result.body, "#EXTM3U\nsegment0.m4s");
});

test("handler rewrites a base64-encoded .m3u8 body and sets bodyEncoding to text", async () => {
  const manifest = "#EXTM3U\nsegment0.m4s";
  const response = {
    status: "200",
    headers: {},
    body: Buffer.from(manifest, "utf-8").toString("base64"),
    bodyEncoding: "base64",
  };
  const event = {
    Records: [
      {
        cf: {
          request: { uri: "/audio/abc/cmaf/playlist.m3u8", querystring: QS },
          response,
        },
      },
    ],
  };

  const result = await handler(event);

  assert.equal(result.bodyEncoding, "text");
  assert.match(result.body, new RegExp(`segment0\\.m4s\\?${QS}$`, "m"));
});
