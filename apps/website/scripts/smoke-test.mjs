#!/usr/bin/env node

const configuredBaseUrl =
  process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:3018"
const baseUrl = configuredBaseUrl.replace(/\/+$/, "")

try {
  new URL(baseUrl)
} catch {
  console.error(`Invalid BASE_URL: ${configuredBaseUrl}`)
  process.exit(1)
}

const checks = [
  {
    path: "/",
    type: "text/html",
    includes: [
      "NOW ON THE APP STORE",
      "https://apps.apple.com/app/tablet-notes/id6748637379",
      'href="/privacy"',
      'href="/terms"',
    ],
  },
  {
    path: "/privacy",
    type: "text/html",
    includes: ["Privacy Policy", "Information We Collect"],
  },
  {
    path: "/terms",
    type: "text/html",
    includes: ["Terms of Use", "1. Acceptance of Terms"],
  },
  {
    path: "/opengraph-image",
    type: "image/png",
  },
  {
    path: "/launch/summary.png",
    type: "image/png",
  },
  {
    path: "/launch/seedance-brand-background.webm",
    type: "video/webm",
  },
]

let failures = 0

for (const check of checks) {
  const url = `${baseUrl}${check.path}`

  try {
    const response = await fetch(url, {
      redirect: "error",
      signal: AbortSignal.timeout(30_000),
      headers: process.env.SMOKE_COOKIE ? { cookie: process.env.SMOKE_COOKIE } : {},
    })
    const contentType = response.headers.get("content-type") ?? ""

    if (!response.ok) {
      throw new Error(`expected a 2xx response, received ${response.status}`)
    }

    if (!contentType.toLowerCase().startsWith(check.type)) {
      throw new Error(`expected ${check.type}, received ${contentType || "no content type"}`)
    }

    if (check.includes) {
      const body = await response.text()
      const missing = check.includes.filter((marker) => !body.includes(marker))

      if (missing.length > 0) {
        throw new Error(`missing page marker(s): ${missing.join(", ")}`)
      }
    } else {
      const body = await response.arrayBuffer()

      if (body.byteLength === 0) {
        throw new Error("received an empty response body")
      }
    }

    console.log(`PASS ${check.path} (${contentType})`)
  } catch (error) {
    failures += 1
    console.error(`FAIL ${check.path}: ${error.message}`)
  }
}

if (failures > 0) {
  console.error(`Smoke test failed: ${failures} check(s) failed against ${baseUrl}`)
  process.exit(1)
}

console.log(`Smoke test passed against ${baseUrl}`)
