"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { Readable } = require("node:stream");
const {
  createHandler,
  propagateQueryStringToManifest,
} = require("./origin-request");

const QS = "Policy=abc&Signature=def&Key-Pair-Id=ghi";

function s3Origin() {
  return {
    domainName: "production-ufb-media.s3.amazonaws.com",
    path: "/production-ufb-media",
  };
}

function fakeS3(manifest) {
  return {
    calls: [],
    send(command) {
      this.calls.push(command.input);
      if (manifest === null) {
        return Promise.reject(new Error("NoSuchKey"));
      }
      return Promise.resolve({
        Body: Readable.from([Buffer.from(manifest, "utf-8")]),
      });
    },
  };
}

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

test("propagateQueryStringToManifest is a no-op with an empty query string", () => {
  const manifest = ["#EXTM3U", "segment0.m4s"].join("\n");

  assert.equal(propagateQueryStringToManifest(manifest, ""), manifest);
});

test("handler passes through non-.m3u8 requests untouched", async () => {
  const s3 = fakeS3(null);
  const handler = createHandler(s3);
  const request = {
    method: "GET",
    uri: "/audio/abc/cmaf/segment0.m4s",
    querystring: QS,
    origin: { s3: s3Origin() },
  };

  const result = await handler({ Records: [{ cf: { request } }] });

  assert.equal(result, request);
  assert.equal(s3.calls.length, 0);
});

test("handler passes through .m3u8 requests with no query string (cookie-authorized browser playback)", async () => {
  const s3 = fakeS3(null);
  const handler = createHandler(s3);
  const request = {
    method: "GET",
    uri: "/audio/abc/cmaf/master.m3u8",
    querystring: "",
    origin: { s3: s3Origin() },
  };

  const result = await handler({ Records: [{ cf: { request } }] });

  assert.equal(result, request);
  assert.equal(s3.calls.length, 0);
});

test("handler passes through non-GET requests untouched", async () => {
  const s3 = fakeS3(null);
  const handler = createHandler(s3);
  const request = {
    method: "OPTIONS",
    uri: "/audio/abc/cmaf/master.m3u8",
    querystring: QS,
    origin: { s3: s3Origin() },
  };

  const result = await handler({ Records: [{ cf: { request } }] });

  assert.equal(result, request);
  assert.equal(s3.calls.length, 0);
});

test("handler fetches and rewrites the manifest, short-circuiting the origin fetch", async () => {
  const manifest = "#EXTM3U\nsegment0.m4s";
  const s3 = fakeS3(manifest);
  const handler = createHandler(s3);
  const request = {
    method: "GET",
    uri: "/audio/abc/cmaf/master.m3u8",
    querystring: QS,
    origin: { s3: s3Origin() },
  };

  const result = await handler({ Records: [{ cf: { request } }] });

  assert.equal(result.status, "200");
  assert.match(result.body, new RegExp(`segment0\\.m4s\\?${QS}$`, "m"));
  assert.deepEqual(s3.calls[0], {
    Bucket: "production-ufb-media",
    Key: "production-ufb-media/audio/abc/cmaf/master.m3u8",
  });
});

test("handler falls back to the real origin fetch when S3 errors", async () => {
  const s3 = fakeS3(null);
  const handler = createHandler(s3);
  const request = {
    method: "GET",
    uri: "/audio/abc/cmaf/master.m3u8",
    querystring: QS,
    origin: { s3: s3Origin() },
  };

  const result = await handler({ Records: [{ cf: { request } }] });

  assert.equal(result, request);
});
