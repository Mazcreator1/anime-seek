addEventListener("fetch", event => {
  event.respondWith(handleRequest(event.request));
});

const errorResponse = (msg, status = 400) =>
  new Response(msg, { status, statusText: "Bad Request" });

async function handleRequest(originalRequest) {
  const originalURL = new URL(originalRequest.url);

  // Require ?url= param
  const rawUrl = originalURL.searchParams.get("url");
  if (!rawUrl) return errorResponse("Error: Cannot get url from param");

  let imageURL;
  try {
    imageURL = new URL(rawUrl);
  } catch {
    return errorResponse("Error: Invalid URL string");
  }

  // Build the fetch request
  let response = await fetch(imageURL.toString(), {
    redirect: "follow",
    headers: {
      referer: imageURL.origin,
      "User-Agent": originalRequest.headers.get("User-Agent") || "trace-proxy",
    },
    cf: { polish: "lossy" }, // optional Cloudflare polish
  });

  // Retry as bot if we didn’t get an image/video
  const ctype = response.headers.get("Content-Type")?.toLowerCase() || "";
  if (
    !ctype.startsWith("image/") &&
    !ctype.startsWith("video/") &&
    !ctype.includes("octet-stream")
  ) {
    const webResponse = await fetch(imageURL.toString(), {
      redirect: "follow",
      headers: {
        referer: imageURL.origin,
        "User-Agent": "googlebot",
      },
    });

    if (webResponse.ok) {
      const html = await webResponse.text();
      const ogImageURL = html.match(/property=["']og:image["']\s+content=["'](.*?)["']/i)?.[1];
      if (ogImageURL?.startsWith("http")) {
        response = await fetch(ogImageURL, {
          redirect: "follow",
          headers: { referer: imageURL.origin },
        });
      }
    }
  }

  if (!response.ok) {
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
    });
  }

  // Final sanity check (don’t hard fail, just warn if unexpected type)
  const finalType = response.headers.get("Content-Type") || "application/octet-stream";
  if (
    !finalType.toLowerCase().startsWith("image/") &&
    !finalType.toLowerCase().startsWith("video/") &&
    !finalType.toLowerCase().includes("octet-stream")
  ) {
    console.warn(`⚠️ Unexpected Content-Type: ${finalType}`);
  }

  const res = new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
  res.headers.set("Access-Control-Allow-Origin", "*");
  return res;
}
